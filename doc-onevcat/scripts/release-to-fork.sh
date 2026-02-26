#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required"
  exit 1
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
SHORT_SHA="$(git rev-parse --short HEAD)"
DEFAULT_TAG="onevcat-v$(date +%Y.%m.%d)-${SHORT_SHA}"
TAG="${1:-$DEFAULT_TAG}"

echo "[release] repository: ${REPO}"
echo "[release] tag: ${TAG}"

if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "error: local tag ${TAG} already exists"
  exit 1
fi

echo "[release] build app"
make build-app

echo "[release] resolve app path from xcodebuild settings"
SETTINGS="$(xcodebuild -project supacode.xcodeproj -scheme supacode -configuration Debug -showBuildSettings -json 2>/dev/null)"
BUILD_DIR="$(echo "$SETTINGS" | jq -r '.[0].buildSettings.BUILT_PRODUCTS_DIR')"
PRODUCT_NAME="$(echo "$SETTINGS" | jq -r '.[0].buildSettings.FULL_PRODUCT_NAME')"
APP_PATH="${BUILD_DIR}/${PRODUCT_NAME}"

if [ ! -d "${APP_PATH}" ]; then
  echo "error: app not found at ${APP_PATH}"
  exit 1
fi

mkdir -p build
ZIP_PATH="build/${PRODUCT_NAME%.app}-${TAG}.app.zip"
NOTES_PATH="build/release-notes-${TAG}.md"

echo "[release] package ${APP_PATH} -> ${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

UPSTREAM_MAIN_SHA="$(git rev-parse --short upstream/main 2>/dev/null || echo unknown)"
cat > "${NOTES_PATH}" <<EOF
Personal fork build for onevcat.

- Commit: ${SHORT_SHA}
- Upstream main (local): ${UPSTREAM_MAIN_SHA}
- Build type: Debug (unsigned)
- Branch: $(git branch --show-current)
EOF

echo "[release] create and push tag ${TAG}"
git tag "${TAG}"
git push origin "${TAG}"

echo "[release] create GitHub Release and upload asset"
gh release create "${TAG}" "${ZIP_PATH}" \
  --repo "${REPO}" \
  --title "Personal build ${TAG}" \
  --notes-file "${NOTES_PATH}"

echo
echo "[done] release created: https://github.com/${REPO}/releases/tag/${TAG}"
