#!/bin/bash
set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/ayang}"
cd "$APP_DIR"

# 默认：宿主机 aaPanel MySQL（network_mode=host 时用 127.0.0.1）
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-xinayang}"
DB_USER="${DB_USER:-xinayang}"
DB_PASS="${DB_PASS:-}"
APP_DEBUG="${APP_DEBUG:-false}"
DEFAULT_TIMEZONE="${DEFAULT_TIMEZONE:-America/New_York}"
FRONTEND_INVITE_BASE="${FRONTEND_INVITE_BASE:-}"
DEFAULT_LANG="${DEFAULT_LANG:-zh-cn}"

if [[ -z "$DB_PASS" ]]; then
  echo "[ayang] 警告: 未设置 DB_PASS。请通过环境变量或 .env.mount 注入数据库密码。"
fi

# 若未挂载外部 .env，则根据环境变量生成
if [[ ! -f "$APP_DIR/.env" ]]; then
  cat > "$APP_DIR/.env" <<EOF
APP_DEBUG = ${APP_DEBUG}

[APP]
DEFAULT_TIMEZONE = ${DEFAULT_TIMEZONE}
FRONTEND_INVITE_BASE =${FRONTEND_INVITE_BASE}

[DATABASE]
TYPE = mysql
HOSTNAME = ${DB_HOST}
DATABASE = ${DB_NAME}
USERNAME = ${DB_USER}
PASSWORD = ${DB_PASS}
HOSTPORT = ${DB_PORT}
CHARSET = utf8
DEBUG = false
prefix = mod_

[LANG]
default_lang = ${DEFAULT_LANG}

[system]
stop = false

[USER]
REG_EMAIL_REQUIRED = false
CAN_MODIFY_BIND_ADDRESS = true
CHECK_USER_ADDRESS = true
PRODUCT_TYPE = 2
ADMIN_GOOGLE_AUTH = false
WITHDRAWAL_DISABLE_MSG = Your withdrawal has been rejected by the system. Please contact online customer service for advice.
EOF
  chown www-data:www-data "$APP_DIR/.env"
  chmod 640 "$APP_DIR/.env"
  echo "[ayang] 已生成 .env（DB=${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}）"
else
  echo "[ayang] 使用已有 .env"
fi

mkdir -p runtime/cache runtime/log runtime/session runtime/backup public/uploads public/tmp
chown -R www-data:www-data runtime public/uploads public/tmp || true
chmod +x docker/scripts/*.sh 2>/dev/null || true

# 可选：探测宿主机 MySQL（不阻塞启动）
if [[ "${WAIT_FOR_DB:-1}" == "1" ]]; then
  echo "[ayang] 探测 MySQL ${DB_HOST}:${DB_PORT} ..."
  if php -r "try { new PDO('mysql:host=${DB_HOST};port=${DB_PORT}', '${DB_USER}', '${DB_PASS}'); exit(0);} catch (Exception \$e) { exit(1);}"; then
    echo "[ayang] MySQL 已就绪"
  else
    echo "[ayang] 警告: MySQL 暂不可达，仍继续启动（请确认 aaPanel 已建库 xinayang 且密码正确）"
  fi
fi

exec "$@"
