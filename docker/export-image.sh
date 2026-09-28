#!/usr/bin/env bash
# 导出 ayang-app 镜像为可搬运的 tar.gz
set -euo pipefail
OUT_DIR="${1:-/www/backup/ayang}"
IMAGE="${IMAGE:-ayang-app:latest}"
mkdir -p "$OUT_DIR"
STAMP=$(date +%Y%m%d_%H%M%S)
OUT="${OUT_DIR}/ayang-app-latest.tar.gz"
OUT_STAMPED="${OUT_DIR}/ayang-app_${STAMP}.tar.gz"

echo "★ exporting ${IMAGE} → ${OUT}"
docker save "$IMAGE" | gzip -1 > "$OUT_STAMPED"
ln -sfn "$(basename "$OUT_STAMPED")" "$OUT"
# 只保留最近 2 个带时间戳的包
ls -1t "${OUT_DIR}"/ayang-app_*.tar.gz 2>/dev/null | tail -n +3 | xargs -r rm -f
ls -lh "$OUT" "$OUT_STAMPED"
echo "★ done"
