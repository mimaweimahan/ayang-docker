#!/bin/bash
# 对齐源站「备份MySQL数据库」：每天导出 xinayang，本地保留 2 份
set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/ayang}"
BACKUP_DIR="${BACKUP_DIR:-$APP_DIR/runtime/backup}"
KEEP="${BACKUP_KEEP:-2}"
LOG="${APP_DIR}/runtime/cron_backup_db.log"

mkdir -p "$BACKUP_DIR"

# 从 .env 读取（entrypoint 已生成）
read_env() {
  local key="$1" default="${2:-}"
  local val
  val=$(grep -E "^${key}\s*=" "$APP_DIR/.env" 2>/dev/null | tail -1 | sed "s/^[^=]*=\s*//" | tr -d '\r' || true)
  echo "${val:-$default}"
}

DB_HOST=$(read_env HOSTNAME "${DB_HOST:-127.0.0.1}")
DB_PORT=$(read_env HOSTPORT "${DB_PORT:-3306}")
DB_NAME=$(read_env DATABASE "${DB_NAME:-xinayang}")
DB_USER=$(read_env USERNAME "${DB_USER:-xinayang}")
DB_PASS=$(read_env PASSWORD "${DB_PASS:-}")

STAMP=$(date +%Y%m%d_%H%M%S)
OUT="${BACKUP_DIR}/${DB_NAME}_${STAMP}.sql.gz"

{
  echo "----------------------------------------------------------------------------"
  echo "★[$(date '+%Y-%m-%d %H:%M:%S')] backup start ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
  if [[ -z "$DB_PASS" ]]; then
    echo "ERROR: empty DB password"
    exit 1
  fi
  # 与源站类似：不要求 PROCESS 权限
  mysqldump -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" \
    --single-transaction --quick --routines --triggers \
    --default-character-set=utf8 --no-tablespaces \
    "$DB_NAME" | gzip -c > "$OUT"
  ls -lh "$OUT"
  # 只保留最新 KEEP 份
  ls -1t "$BACKUP_DIR"/${DB_NAME}_*.sql.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | xargs -r rm -f
  echo "★[$(date '+%Y-%m-%d %H:%M:%S')] Successful keep=${KEEP}"
  echo "----------------------------------------------------------------------------"
} >>"$LOG" 2>&1
