#!/usr/bin/env bash
set -euo pipefail

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

default_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}'
}

team_id_from_identity() {
  local identity="$1"
  if [[ "$identity" =~ \(([A-Z0-9]{10})\)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

submit_with_keychain_profile() {
  local artifact_path="$1"
  local output

  set +e
  output="$(xcrun notarytool submit "$artifact_path" --keychain-profile "$KEYCHAIN_PROFILE" --wait 2>&1)"
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    echo "$output"
    return 0
  fi

  echo "$output" >&2
  if [[ "$output" == *"No Keychain password item found for profile"* ]] \
    || [[ "$output" == *"profile"* && "$output" == *"not found"* ]]
  then
    return 2
  fi

  return $status
}

store_notary_credentials() {
  local key_path="${APPLE_NOTARIZATION_KEY_PATH:-}"
  local key_id="${APPLE_NOTARIZATION_KEY_ID:-}"
  local issuer="${APPLE_NOTARIZATION_ISSUER:-}"

  if [[ -n "$key_path" || -n "$key_id" || -n "$issuer" ]]; then
    if [[ -z "$key_path" || -z "$key_id" || -z "$issuer" ]]; then
      echo "error: APPLE_NOTARIZATION_KEY_PATH/KEY_ID/ISSUER must all be set"
      exit 1
    fi
    if [[ ! -f "$key_path" ]]; then
      echo "error: APPLE_NOTARIZATION_KEY_PATH does not exist: $key_path"
      exit 1
    fi
    xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
      --key "$key_path" \
      --key-id "$key_id" \
      --issuer "$issuer"
    return
  fi

  if [[ -z "$APPLE_ID_INPUT" ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Apple ID email for notarization: " APPLE_ID_INPUT
    else
      echo "error: APPLE_ID is required when no key-based notarization credentials are provided"
      exit 1
    fi
  fi

  if [[ -z "$APPLE_PASSWORD_INPUT" ]]; then
    if [[ -t 0 ]]; then
      read -r -s -p "App-specific password (input hidden): " APPLE_PASSWORD_INPUT
      echo
    else
      echo "error: APPLE_PASSWORD is required when no key-based notarization credentials are provided"
      exit 1
    fi
  fi

  if [[ -z "$TEAM_ID_INPUT" ]]; then
    TEAM_ID_INPUT="$(team_id_from_identity "$SIGNING_IDENTITY" || true)"
  fi
  if [[ -z "$TEAM_ID_INPUT" ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Apple Team ID: " TEAM_ID_INPUT
    else
      echo "error: APPLE_TEAM_ID is required when it cannot be inferred from signing identity"
      exit 1
    fi
  fi

  xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
    --apple-id "$APPLE_ID_INPUT" \
    --password "$APPLE_PASSWORD_INPUT" \
    --team-id "$TEAM_ID_INPUT"
}

sign_and_notarize_app() {
  local app_path="$1"
  local submission_zip="$2"

  echo "[release] codesigning app with identity: $SIGNING_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"

  echo "[release] create notarization artifact: $submission_zip"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_zip"

  echo "[release] notarizing artifact..."
  if submit_with_keychain_profile "$submission_zip"; then
    echo "[release] used keychain profile: $KEYCHAIN_PROFILE"
  else
    local notary_status=$?
    if [[ $notary_status -ne 2 ]]; then
      exit "$notary_status"
    fi

    echo "[release] keychain profile not found: $KEYCHAIN_PROFILE"
    echo "[release] storing notarization credentials..."
    store_notary_credentials
    xcrun notarytool submit "$submission_zip" --keychain-profile "$KEYCHAIN_PROFILE" --wait
  fi

  echo "[release] staple notarization ticket to app"
  xcrun stapler staple "$app_path"
  xcrun stapler validate "$app_path"
}

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required"
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this script only supports macOS"
  exit 1
fi

REPO="${GH_REPO:-$(origin_repo_from_remote || true)}"
if [[ -z "${REPO}" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

SHORT_SHA="$(git rev-parse --short HEAD)"
DEFAULT_TAG="onevcat-v$(date +%Y.%m.%d)-${SHORT_SHA}"
TAG="${1:-$DEFAULT_TAG}"
KEYCHAIN_PROFILE="${APPLE_NOTARY_KEYCHAIN_PROFILE:-supacode-notary}"
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
TEAM_ID_INPUT="${APPLE_TEAM_ID:-}"
APPLE_ID_INPUT="${APPLE_ID:-}"
APPLE_PASSWORD_INPUT="${APPLE_PASSWORD:-}"

if [[ "${ENABLE_NOTARIZATION:-1}" != "1" ]]; then
  echo "error: publishing non-notarized releases is forbidden for this fork"
  echo "error: remove ENABLE_NOTARIZATION=0 and provide notarization credentials"
  exit 1
fi
ENABLE_NOTARIZATION="1"

echo "[release] repository: ${REPO}"
echo "[release] tag: ${TAG}"
echo "[release] notarization: ${ENABLE_NOTARIZATION}"

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
SUBMISSION_ZIP="build/notary-submit-${TAG}.app.zip"
BUILD_TYPE="Debug (Developer ID signed + notarized)"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun is required for notarization"
  exit 1
fi
if ! command -v codesign >/dev/null 2>&1; then
  echo "error: codesign is required for notarization"
  exit 1
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(default_signing_identity || true)"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "error: APPLE_SIGNING_IDENTITY is not set and no Developer ID Application identity was found"
  exit 1
fi
sign_and_notarize_app "${APP_PATH}" "${SUBMISSION_ZIP}"

echo "[release] package ${APP_PATH} -> ${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

UPSTREAM_MAIN_SHA="$(git rev-parse --short upstream/main 2>/dev/null || echo unknown)"
cat > "${NOTES_PATH}" <<EOF
Personal fork build for onevcat.

- Commit: ${SHORT_SHA}
- Upstream main (local): ${UPSTREAM_MAIN_SHA}
- Build type: ${BUILD_TYPE}
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
