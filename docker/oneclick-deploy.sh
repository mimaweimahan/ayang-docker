#!/usr/bin/env bash
# 新 VPS 一条命令部署 ayang-app（镜像包 + compose，不含 MySQL）
# 用法:
#   DB_PASS='库密码' bash oneclick-deploy.sh /path/to/ayang-app-latest.tar.gz
#   或把镜像包与本脚本同目录后:
#   DB_PASS='库密码' bash oneclick-deploy.sh
set -euo pipefail

APP_DIR="${APP_DIR:-/www/wwwroot/ayang-docker}"
IMAGE_TAR="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$IMAGE_TAR" ]]; then
  for c in \
    "${SCRIPT_DIR}/ayang-app-latest.tar.gz" \
    /www/backup/ayang/ayang-app-latest.tar.gz \
    ./ayang-app-latest.tar.gz
  do
    [[ -f "$c" ]] && IMAGE_TAR="$c" && break
  done
fi

if [[ -z "${IMAGE_TAR}" || ! -f "$IMAGE_TAR" ]]; then
  echo "ERROR: 找不到镜像包 ayang-app-latest.tar.gz"
  echo "用法: DB_PASS='xxx' bash oneclick-deploy.sh /path/to/ayang-app-latest.tar.gz"
  exit 1
fi

if [[ -z "${DB_PASS:-}" ]]; then
  echo "ERROR: 请设置环境变量 DB_PASS（aaPanel 里 xinayang 库密码）"
  exit 1
fi

command -v docker >/dev/null || { echo "ERROR: 未安装 docker"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "ERROR: 需要 docker compose 插件"; exit 1; }

echo "★ 1/4 load image: $IMAGE_TAR"
gunzip -c "$IMAGE_TAR" | docker load

echo "★ 2/4 prepare $APP_DIR"
mkdir -p "$APP_DIR/docker"
# 若已有 compose 则沿用；否则从脚本旁拷贝
if [[ ! -f "$APP_DIR/docker/docker-compose.yml" ]]; then
  if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    cp -a "$SCRIPT_DIR/docker-compose.yml" "$SCRIPT_DIR/.env.docker.example" \
      "$SCRIPT_DIR/README.md" "$APP_DIR/docker/" 2>/dev/null || true
    # compose 的 build 在无源码时用不上，仅用 image
  else
    cat > "$APP_DIR/docker/docker-compose.yml" <<'YML'
services:
  ayang:
    image: ayang-app:latest
    container_name: ayang-app
    restart: unless-stopped
    network_mode: host
    environment:
      DB_HOST: "127.0.0.1"
      DB_PORT: "3306"
      DB_NAME: "xinayang"
      DB_USER: "xinayang"
      DB_PASS: "${DB_PASS:?请设置 DB_PASS}"
      APP_DEBUG: "false"
      DEFAULT_TIMEZONE: "America/New_York"
      FRONTEND_INVITE_BASE: "${FRONTEND_INVITE_BASE:-}"
      WAIT_FOR_DB: "${WAIT_FOR_DB:-1}"
      BACKUP_KEEP: "${BACKUP_KEEP:-2}"
    volumes:
      - ayang_uploads:/var/www/ayang/public/uploads
      - ayang_runtime:/var/www/ayang/runtime
      - ayang_db_backup:/var/www/ayang/runtime/backup
volumes:
  ayang_uploads:
  ayang_runtime:
  ayang_db_backup:
YML
  fi
fi

cat > "$APP_DIR/docker/.env.docker" <<ENV
DB_PASS=${DB_PASS}
FRONTEND_INVITE_BASE=${FRONTEND_INVITE_BASE:-}
WAIT_FOR_DB=${WAIT_FOR_DB:-1}
BACKUP_KEEP=${BACKUP_KEEP:-2}
ENV

echo "★ 3/4 start container"
cd "$APP_DIR"
docker compose -f docker/docker-compose.yml --env-file docker/.env.docker up -d

echo "★ 4/4 check"
sleep 2
docker ps --filter name=ayang-app --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl -sI http://127.0.0.1:8088/ | head -5 || true
echo
echo "完成。前提：aaPanel 已建库 xinayang 并导入数据；可选反代到 :8088"
echo "日志: docker logs -f ayang-app"
