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

origin_repo_from_remote() {
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "${remote_url}" ]]; then
    return 1
  fi

  # Supports:
  # - git@github.com:owner/repo.git
  # - ssh://git@github.com/owner/repo.git
  # - https://github.com/owner/repo.git
  local repo
  repo="$(echo "${remote_url}" | sed -E 's#^(git@github.com:|ssh://git@github.com/|https://github.com/)##; s#\.git$##')"
  if [[ "${repo}" == */* ]]; then
    echo "${repo}"
    return 0
  fi
  return 1
}

REPO="${GH_REPO:-$(origin_repo_from_remote || true)}"
if [[ -z "${REPO}" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

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
if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  echo "[release] release already exists, upload asset with --clobber"
  gh release upload "${TAG}" "${ZIP_PATH}" --clobber --repo "${REPO}"
else
  CREATE_ERR="$(mktemp)"
  if gh release create "${TAG}" "${ZIP_PATH}" \
    --repo "${REPO}" \
    --title "Personal build ${TAG}" \
    --notes-file "${NOTES_PATH}" \
    2>"${CREATE_ERR}"
  then
    rm -f "${CREATE_ERR}"
  else
    echo "[release] gh release create failed, fallback to gh api + upload"
    cat "${CREATE_ERR}"
    rm -f "${CREATE_ERR}"

    if ! gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
      RELEASE_NOTES="$(cat "${NOTES_PATH}")"
      PAYLOAD="$(jq -n \
        --arg tag "${TAG}" \
        --arg name "Personal build ${TAG}" \
        --arg body "${RELEASE_NOTES}" \
        '{tag_name: $tag, name: $name, body: $body, draft: false, prerelease: false}')"
      gh api -X POST "repos/${REPO}/releases" --input - <<<"${PAYLOAD}" >/dev/null
    fi

    gh release upload "${TAG}" "${ZIP_PATH}" --clobber --repo "${REPO}"
  fi
fi

echo
echo "[done] release created: https://github.com/${REPO}/releases/tag/${TAG}"
