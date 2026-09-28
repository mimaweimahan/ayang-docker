#!/usr/bin/env bash
# 推送镜像到 GHCR（可选 Release tar）
set -euo pipefail
OWNER="${GITHUB_OWNER:?请设置 GITHUB_OWNER}"
REPO="${GITHUB_REPO:-ayang-deploy}"
IMAGE_LOCAL="${IMAGE_LOCAL:-ayang-app:latest}"
IMAGE_REMOTE="ghcr.io/${OWNER}/ayang-app:latest"
TAG_DATE=$(date +%Y%m%d)
[[ -n "${GH_TOKEN:-}" ]] || { echo "ERROR: 需要 GH_TOKEN"; exit 1; }

echo "$GH_TOKEN" | docker login ghcr.io -u "${GITHUB_USER:-$OWNER}" --password-stdin
docker tag "$IMAGE_LOCAL" "$IMAGE_REMOTE"
docker tag "$IMAGE_LOCAL" "ghcr.io/${OWNER}/ayang-app:${TAG_DATE}"
docker push "$IMAGE_REMOTE"
docker push "ghcr.io/${OWNER}/ayang-app:${TAG_DATE}"
echo "★ pushed ${IMAGE_REMOTE} 与 :${TAG_DATE}"

if [[ "${UPLOAD_RELEASE:-0}" == "1" ]]; then
  command -v gh >/dev/null || { echo "ERROR: 需要 gh CLI"; exit 1; }
  OUT="/tmp/ayang-app-latest.tar.gz"
  docker save "$IMAGE_LOCAL" | gzip -1 > "$OUT"
  if gh release view "image-${TAG_DATE}" -R "${OWNER}/${REPO}" >/dev/null 2>&1; then
    gh release upload "image-${TAG_DATE}" "$OUT" -R "${OWNER}/${REPO}" --clobber
  else
    gh release create "image-${TAG_DATE}" "$OUT" -R "${OWNER}/${REPO}" -t "Image ${TAG_DATE}" -n "ayang-app docker image"
  fi
  if gh release view latest -R "${OWNER}/${REPO}" >/dev/null 2>&1; then
    gh release upload latest "$OUT" -R "${OWNER}/${REPO}" --clobber
  else
    gh release create latest "$OUT" -R "${OWNER}/${REPO}" -t "Latest image" -n "最新镜像包" || true
  fi
  echo "★ release asset uploaded"
fi
echo done
