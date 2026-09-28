#!/bin/bash
# 对齐源站「ql」：清理日志（容器内改为清应用/Nginx/运行时日志，而非宿主机 /var/log）
set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/ayang}"
LOG="${APP_DIR}/runtime/cron_ql.log"

{
  echo "----------------------------------------------------------------------------"
  echo "★[$(date '+%Y-%m-%d %H:%M:%S')] ql clean start"

  # 运行时业务日志（按月目录可整目录清空旧内容，保留目录结构）
  find "$APP_DIR/runtime" -type f \( -name '*.log' -o -name '*.txt' \) \
    ! -name 'cron_ql.log' \
    -mtime +7 -delete 2>/dev/null || true

  # session / cache 垃圾
  find "$APP_DIR/runtime/session" -type f -name 'sess_*' -mtime +7 -delete 2>/dev/null || true
  find "$APP_DIR/runtime/cache" -type f -mtime +3 -delete 2>/dev/null || true

  # 容器内 nginx 日志截断
  for f in /var/log/nginx/*.log; do
    [[ -f "$f" ]] && : > "$f" || true
  done

  # supervisor 日志过大时截断
  for f in /var/log/supervisor/*.log; do
    [[ -f "$f" ]] || continue
    size=$(stat -c%s "$f" 2>/dev/null || echo 0)
    if [[ "$size" -gt 10485760 ]]; then
      : > "$f"
    fi
  done

  echo "★[$(date '+%Y-%m-%d %H:%M:%S')] Successful"
  echo "----------------------------------------------------------------------------"
} >>"$LOG" 2>&1
