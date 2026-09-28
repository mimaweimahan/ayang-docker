#!/usr/bin/env bash
# ayang 新 VPS 一键部署（私有仓 + Release 镜像/SQL）
# 示例：
#   export GH_TOKEN=xxx DB_PASS=xxx
#   curl -fsSL -H "Authorization: token $GH_TOKEN" \
#     https://raw.githubusercontent.com/mimaweimahan/ayang-docker/main/scripts/bootstrap.sh \
#     -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh --with-mysql
set -euo pipefail

OWNER="${GITHUB_OWNER:-mimaweimahan}"
REPO="${GITHUB_REPO:-ayang-docker}"
BRANCH="${GITHUB_BRANCH:-main}"
APP_DIR="${APP_DIR:-/www/wwwroot/ayang-docker}"
WITH_MYSQL=0
SQL_INIT_FILE="${SQL_INIT_FILE:-}"
HTTP_PORT="${HTTP_PORT:-8088}"
FRONTEND_INVITE_BASE="${FRONTEND_INVITE_BASE:-}"
SKIP_SQL=0

usage() {
  cat <<'USAGE'
用法:
  GH_TOKEN=xxx DB_PASS=xxx bash bootstrap.sh [选项]

选项:
  --with-mysql          容器自带 MySQL（全自动，不依赖 aaPanel）
  --sql-file PATH       指定初始化 SQL.gz；默认自动从 Release 下载 xinayang.sql.gz
  --skip-sql            不导入 SQL（空库，仅调试）
  --app-dir PATH        部署目录（默认 /www/wwwroot/ayang-docker）
  --image REF           镜像名（默认 ayang-app:latest，优先 Release 包）
  --owner NAME          GitHub 用户名（默认 mimaweimahan）
  --repo NAME           仓库名（默认 ayang-docker）
  -h, --help            帮助
USAGE
}

AYANG_IMAGE="${AYANG_IMAGE:-ayang-app:latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-mysql) WITH_MYSQL=1; shift ;;
    --sql-file) SQL_INIT_FILE="$2"; shift 2 ;;
    --skip-sql) SKIP_SQL=1; shift ;;
    --app-dir) APP_DIR="$2"; shift 2 ;;
    --image) AYANG_IMAGE="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "ERROR: 私有仓库需要 GH_TOKEN（GitHub PAT，至少 repo 权限）"
  exit 1
fi
if [[ -z "${DB_PASS:-}" ]]; then
  echo "ERROR: 请设置 DB_PASS"
  exit 1
fi
if [[ "$WITH_MYSQL" -eq 1 && -z "${MYSQL_ROOT_PASSWORD:-}" ]]; then
  MYSQL_ROOT_PASSWORD="${DB_PASS}"
  export MYSQL_ROOT_PASSWORD
  echo "INFO: MYSQL_ROOT_PASSWORD 未设置，已与 DB_PASS 相同"
fi

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
AUTH=(-H "Authorization: token ${GH_TOKEN}" -H "Accept: application/vnd.github+json")

echo "★ [1/7] 安装依赖（docker / git / curl）"
if ! command -v curl >/dev/null 2>&1; then
  (dnf install -y curl || yum install -y curl || apt-get update && apt-get install -y curl) || true
fi
if ! command -v git >/dev/null 2>&1; then
  echo "→ 安装 git..."
  (dnf install -y git || yum install -y git || apt-get update && apt-get install -y git)
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "→ 安装 Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker || service docker start || true
fi
docker compose version >/dev/null

echo "★ [2/7] 拉取仓库 ${OWNER}/${REPO}@${BRANCH}"
mkdir -p "$(dirname "$APP_DIR")"
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${OWNER}/${REPO}.git"
  git -C "$APP_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$APP_DIR" checkout -f "FETCH_HEAD"
else
  rm -rf "$APP_DIR"
  git clone --depth 1 -b "$BRANCH" \
    "https://x-access-token:${GH_TOKEN}@github.com/${OWNER}/${REPO}.git" "$APP_DIR"
fi
cd "$APP_DIR"
git remote set-url origin "https://github.com/${OWNER}/${REPO}.git" 2>/dev/null || true

download_release_asset() {
  local name="$1" dest="$2"
  echo "→ 下载 Release 资产: $name"
  local api="https://api.github.com/repos/${OWNER}/${REPO}/releases/tags/latest"
  local url
  url=$(curl -fsSL "${AUTH[@]}" "$api" | ASSET_NAME="$name" python3 -c '
import sys, json, os
name = os.environ["ASSET_NAME"]
rel = json.load(sys.stdin)
for a in rel.get("assets", []):
    if a.get("name") == name:
        print(a["url"])
        break
else:
    raise SystemExit("Release 中找不到资产: " + name)
')
  curl -fsSL "${AUTH[@]}" -H "Accept: application/octet-stream" -L "$url" -o "$dest"
  ls -lh "$dest"
}

echo "★ [3/7] 获取应用镜像"
mkdir -p /tmp/ayang-deploy
# 优先 Release tar（不依赖 GHCR packages 权限）；已有本地镜像则跳过
if docker image inspect "$AYANG_IMAGE" >/dev/null 2>&1; then
  echo "→ 本地已有镜像 $AYANG_IMAGE"
elif docker pull "$AYANG_IMAGE" 2>/dev/null; then
  echo "→ 已从仓库拉取 $AYANG_IMAGE"
else
  ASSET="ayang-app-latest.tar.gz"
  download_release_asset "$ASSET" "/tmp/ayang-deploy/$ASSET"
  gunzip -c "/tmp/ayang-deploy/$ASSET" | docker load
  # load 出来一般是 ayang-app:latest
  if [[ "$AYANG_IMAGE" != "ayang-app:latest" ]]; then
    docker tag ayang-app:latest "$AYANG_IMAGE" || true
  fi
fi
# compose 默认用 ayang-app:latest
AYANG_IMAGE="ayang-app:latest"

echo "★ [4/7] 准备数据库初始化 SQL"
if [[ "$WITH_MYSQL" -eq 1 && "$SKIP_SQL" -eq 0 ]]; then
  if [[ -z "$SQL_INIT_FILE" ]]; then
    SQL_INIT_FILE="/tmp/ayang-deploy/xinayang.sql.gz"
    download_release_asset "xinayang.sql.gz" "$SQL_INIT_FILE"
  fi
  [[ -f "$SQL_INIT_FILE" ]] || { echo "ERROR: 找不到 SQL: $SQL_INIT_FILE"; exit 1; }
  gzip -t "$SQL_INIT_FILE" 2>/dev/null || { echo "ERROR: SQL 不是有效 gzip: $SQL_INIT_FILE"; exit 1; }
elif [[ "$WITH_MYSQL" -eq 0 ]]; then
  echo "→ 宿主机 MySQL 模式：请确认 aaPanel 已建 xinayang 并导入数据"
  if ! php -r true 2>/dev/null; then
    # 用 docker 临时探测可选；这里用 timeout+bash /dev/tcp
    if ! timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/3306" 2>/dev/null; then
      echo "WARN: 127.0.0.1:3306 不通，容器启动后可能连不上库"
    fi
  fi
fi

echo "★ [5/7] 写环境配置"
mkdir -p docker
cat > docker/.env.docker <<ENV
DB_PASS=${DB_PASS}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-${DB_PASS}}
FRONTEND_INVITE_BASE=${FRONTEND_INVITE_BASE}
WAIT_FOR_DB=1
BACKUP_KEEP=2
AYANG_IMAGE=${AYANG_IMAGE}
HTTP_PORT=${HTTP_PORT}
MYSQL_PORT=${MYSQL_PORT:-3306}
ENV
if [[ "$WITH_MYSQL" -eq 1 && "$SKIP_SQL" -eq 0 ]]; then
  echo "SQL_INIT_FILE=${SQL_INIT_FILE}" >> docker/.env.docker
fi

echo "★ [6/7] 启动容器"
if [[ "$WITH_MYSQL" -eq 1 ]]; then
  COMPOSE_FILES=(-f docker/docker-compose.portable.yml)
  if [[ "$SKIP_SQL" -eq 0 ]]; then
    COMPOSE_FILES+=(-f docker/docker-compose.init-sql.yml)
  fi
  docker compose "${COMPOSE_FILES[@]}" --env-file docker/.env.docker up -d
else
  docker compose -f docker/docker-compose.yml --env-file docker/.env.docker up -d
fi

echo "★ [7/7] 健康检查"
# MySQL 初始化可能较久，多等一会
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS -o /dev/null -w "%{http_code}" "http://127.0.0.1:${HTTP_PORT}/" | grep -qE '200|301|302|303|404'; then
    break
  fi
  echo "→ 等待服务就绪 ($i/10)..."
  sleep 5
done
docker ps --filter name=ayang --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo "HTTP:"
curl -sI "http://127.0.0.1:${HTTP_PORT}/" | head -8 || true
echo
echo "=========================================="
echo "部署完成"
echo "访问: http://服务器IP:${HTTP_PORT}/"
echo "日志: docker logs -f ayang-app"
if [[ "$WITH_MYSQL" -eq 1 ]]; then
  echo "MySQL: 容器 ayang-mysql，库 xinayang / 用户 xinayang / 密码=DB_PASS"
fi
echo "=========================================="
