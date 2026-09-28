#!/usr/bin/env bash
# ayang 新 VPS 一键部署
set -euo pipefail

OWNER="${GITHUB_OWNER:-OWNER}"
REPO="${GITHUB_REPO:-ayang-deploy}"
BRANCH="${GITHUB_BRANCH:-main}"
APP_DIR="${APP_DIR:-/www/wwwroot/ayang-docker}"
AYANG_IMAGE="${AYANG_IMAGE:-ghcr.io/${OWNER}/ayang-app:latest}"
WITH_MYSQL=0
SQL_INIT_FILE="${SQL_INIT_FILE:-}"
HTTP_PORT="${HTTP_PORT:-8088}"
FRONTEND_INVITE_BASE="${FRONTEND_INVITE_BASE:-}"

usage() {
  cat <<USAGE
用法:
  GH_TOKEN=xxx DB_PASS=xxx [MYSQL_ROOT_PASSWORD=xxx] bash bootstrap.sh [选项]

选项:
  --with-mysql          容器自带 MySQL（全自动，不依赖 aaPanel）
  --sql-file PATH       配合 --with-mysql，首次导入的 .sql.gz
  --app-dir PATH        部署目录（默认 /www/wwwroot/ayang-docker）
  --image REF           镜像（默认 ghcr.io/$GITHUB_OWNER/ayang-app:latest）
  --owner NAME          GitHub 用户或组织名
  --repo NAME           仓库名（默认 ayang-deploy）
  -h, --help            帮助
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-mysql) WITH_MYSQL=1; shift ;;
    --sql-file) SQL_INIT_FILE="$2"; shift 2 ;;
    --app-dir) APP_DIR="$2"; shift 2 ;;
    --image) AYANG_IMAGE="$2"; shift 2 ;;
    --owner) OWNER="$2"; AYANG_IMAGE="ghcr.io/${OWNER}/ayang-app:latest"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "${DB_PASS:-}" ]]; then
  echo "ERROR: 请设置 DB_PASS"; exit 1
fi
if [[ "$WITH_MYSQL" -eq 1 && -z "${MYSQL_ROOT_PASSWORD:-}" ]]; then
  MYSQL_ROOT_PASSWORD="${DB_PASS}"
  export MYSQL_ROOT_PASSWORD
  echo "INFO: MYSQL_ROOT_PASSWORD 未设置，已与 DB_PASS 相同"
fi

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

echo "★ [1/6] 检查 Docker"
if ! command -v docker >/dev/null 2>&1; then
  echo "→ 安装 Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker || true
fi
docker compose version >/dev/null

echo "★ [2/6] 拉取部署仓库 ${OWNER}/${REPO}"
mkdir -p "$(dirname "$APP_DIR")"
if [[ -d "$APP_DIR/.git" ]]; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    git -C "$APP_DIR" remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${OWNER}/${REPO}.git"
  fi
  git -C "$APP_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$APP_DIR" checkout -f "FETCH_HEAD"
else
  rm -rf "$APP_DIR"
  if [[ -n "${GH_TOKEN:-}" ]]; then
    git clone --depth 1 -b "$BRANCH" "https://x-access-token:${GH_TOKEN}@github.com/${OWNER}/${REPO}.git" "$APP_DIR"
  else
    git clone --depth 1 -b "$BRANCH" "https://github.com/${OWNER}/${REPO}.git" "$APP_DIR"
  fi
fi
cd "$APP_DIR"
git remote set-url origin "https://github.com/${OWNER}/${REPO}.git" 2>/dev/null || true

echo "★ [3/6] 登录 GHCR 并拉取镜像 ${AYANG_IMAGE}"
if [[ -n "${GH_TOKEN:-}" ]]; then
  echo "$GH_TOKEN" | docker login ghcr.io -u "${GITHUB_USER:-${OWNER}}" --password-stdin
fi
if ! docker pull "$AYANG_IMAGE"; then
  echo "WARN: docker pull 失败，尝试从 GitHub Release 下载镜像包..."
  ASSET="ayang-app-latest.tar.gz"
  mkdir -p /tmp
  AUTH_HEADER=()
  [[ -n "${GH_TOKEN:-}" ]] && AUTH_HEADER=(-H "Authorization: token ${GH_TOKEN}")
  curl -fsSL "${AUTH_HEADER[@]}" -L \
    "https://github.com/${OWNER}/${REPO}/releases/latest/download/${ASSET}" \
    -o "/tmp/${ASSET}"
  gunzip -c "/tmp/${ASSET}" | docker load
  docker tag ayang-app:latest "$AYANG_IMAGE" 2>/dev/null || true
fi

echo "★ [4/6] 写环境配置"
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
[[ -n "$SQL_INIT_FILE" ]] && echo "SQL_INIT_FILE=${SQL_INIT_FILE}" >> docker/.env.docker

echo "★ [5/6] 启动"
if [[ "$WITH_MYSQL" -eq 1 ]]; then
  COMPOSE_FILES=(-f docker/docker-compose.portable.yml)
  if [[ -n "$SQL_INIT_FILE" ]]; then
    [[ -f "$SQL_INIT_FILE" ]] || { echo "ERROR: SQL 文件不存在 $SQL_INIT_FILE"; exit 1; }
    COMPOSE_FILES+=(-f docker/docker-compose.init-sql.yml)
  fi
  docker compose "${COMPOSE_FILES[@]}" --env-file docker/.env.docker pull || true
  docker compose "${COMPOSE_FILES[@]}" --env-file docker/.env.docker up -d
else
  echo "模式: 宿主机 MySQL（请确认 aaPanel 已建 xinayang 并导入数据）"
  docker compose -f docker/docker-compose.yml --env-file docker/.env.docker up -d
fi

echo "★ [6/6] 健康检查"
sleep 3
docker ps --filter name=ayang --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl -sI "http://127.0.0.1:${HTTP_PORT}/" | head -5 || true
echo
echo "完成。访问: http://服务器IP:${HTTP_PORT}/"
echo "日志: docker logs -f ayang-app"
