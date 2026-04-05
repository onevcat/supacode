#!/usr/bin/env bash
# Prowl release script: bump, build, sign, notarize, and publish.
#
# Usage: ./doc-onevcat/scripts/release.sh [VERSION]
#
# Prerequisites:
#   Run ./doc-onevcat/scripts/release-notes.sh first to generate and review
#   build/release-notes.md. This script will refuse to proceed without it.
#
# Environment variables:
#   APPLE_SIGNING_IDENTITY          Developer ID identity (auto-detected if unset)
#   APPLE_TEAM_ID                   Apple Team ID (inferred from identity if unset)
#   APPLE_NOTARY_KEYCHAIN_PROFILE   Keychain profile for notarytool (default: supacode-notary)
#   SPARKLE_PRIVATE_KEY_FILE        Path to EdDSA private key file (default: ~/.prowl-sparkle-private-key)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

# ── Helpers ──────────────────────────────────────────────────────────────────

origin_repo_from_remote() {
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  [[ -z "$remote_url" ]] && return 1
  local repo
  repo="$(echo "$remote_url" | sed -E 's#^(git@github.com:|ssh://git@github.com/|https://github.com/)##; s#\.git$##')"
  [[ "$repo" == */* ]] && echo "$repo" && return 0
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

signing_identity_sha() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep "$1" | head -1 | awk '{print $2}'
}

log() { echo "[release] $*"; }
die() { echo "error: $*" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────

log "preflight checks..."

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only"
for cmd in gh jq codesign xcrun create-dmg; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required but not found"
done
[[ -x "$PROJECT_DIR/bins/generate_appcast" ]] || die "bins/generate_appcast not found"

if [[ -n "$(git status --porcelain)" ]]; then
  die "working tree is not clean — commit or stash changes first"
fi

REPO="${GH_REPO:-$(origin_repo_from_remote || true)}"
[[ -z "$REPO" ]] && REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
[[ -z "$REPO" ]] && die "cannot determine GitHub repository"

KEYCHAIN_PROFILE="${APPLE_NOTARY_KEYCHAIN_PROFILE:-supacode-notary}"
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-$(default_signing_identity || true)}"
[[ -z "$SIGNING_IDENTITY" ]] && die "no Developer ID Application identity found — set APPLE_SIGNING_IDENTITY"

TEAM_ID="${APPLE_TEAM_ID:-$(team_id_from_identity "$SIGNING_IDENTITY" || true)}"
[[ -z "$TEAM_ID" ]] && die "cannot determine Apple Team ID — set APPLE_TEAM_ID"

IDENTITY_SHA="$(signing_identity_sha "$SIGNING_IDENTITY")"
[[ -z "$IDENTITY_SHA" ]] && die "cannot find signing identity SHA for: $SIGNING_IDENTITY"

SPARKLE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$HOME/.prowl-sparkle-private-key}"
[[ -f "$SPARKLE_KEY_FILE" ]] || die "Sparkle private key not found: $SPARKLE_KEY_FILE"

NOTES_FILE="build/release-notes.md"
[[ -s "$NOTES_FILE" ]] || die "$NOTES_FILE not found — run release-notes.sh first"

log "repository: $REPO"
log "signing identity: $SIGNING_IDENTITY"
log "team ID: $TEAM_ID"

# ── Version ──────────────────────────────────────────────────────────────────

if [[ -n "${1:-}" ]]; then
  VERSION="$1"
  if ! echo "$VERSION" | grep -qE '^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}(\.[0-9]+)?$'; then
    die "VERSION must be in YYYY.M.DD or YYYY.M.DD.N format"
  fi
else
  VERSION="$(date +%Y.%-m.%-d)"
  suffix=1
  while git rev-parse "v$VERSION" >/dev/null 2>&1; do
    suffix=$((suffix + 1))
    VERSION="$(date +%Y.%-m.%-d).$suffix"
  done
fi

TAG="v$VERSION"

BUILD="$(date +%Y%m%d)"
CURRENT_BUILD="$(/usr/bin/awk -F' = ' '/CURRENT_PROJECT_VERSION = [0-9]+;/{gsub(/;/,""); print $2; exit}' "$PROJECT_DIR/supacode.xcodeproj/project.pbxproj")"
if [[ "$CURRENT_BUILD" -ge "$BUILD" ]] 2>/dev/null; then
  BUILD="$((CURRENT_BUILD + 1))"
fi

log "version: $VERSION (build $BUILD), tag: $TAG"

# ── Bump version (skip if tag already exists) ────────────────────────────────

if git rev-parse "$TAG" >/dev/null 2>&1; then
  log "tag $TAG already exists, skipping bump"
else
  log "bumping version in project..."
  make bump-version VERSION="$VERSION" BUILD="$BUILD"
fi

# ── Update CHANGELOG ────────────────────────────────────────────────────────

CHANGELOG="CHANGELOG.md"
ENTRY_HEADER="## [$VERSION](https://github.com/$REPO/releases/tag/$TAG)"

if [[ -f "$CHANGELOG" ]] && grep -qF "$ENTRY_HEADER" "$CHANGELOG"; then
  log "CHANGELOG already contains entry for $VERSION, skipping"
else
  log "updating CHANGELOG.md..."
  {
    echo "# Changelog"
    echo ""
    echo "$ENTRY_HEADER"
    echo ""
    cat "$NOTES_FILE"
    echo ""
    if [[ -f "$CHANGELOG" ]]; then
      # Skip the "# Changelog" header and leading blank line
      tail -n +3 "$CHANGELOG"
    fi
  } > "${CHANGELOG}.tmp"
  mv "${CHANGELOG}.tmp" "$CHANGELOG"
  git add "$CHANGELOG"
  git commit -m "Update CHANGELOG for $VERSION"
  # Move tag to include the CHANGELOG commit
  git tag -f "$TAG" HEAD
fi

# ── Show release notes ───────────────────────────────────────────────────────

echo
echo "──── Release Notes ────"
cat "$NOTES_FILE"
echo "───────────────────────"
echo

# Confirm interactively if possible
if [[ -t 0 ]]; then
  read -rp "Proceed with release? [Y/n] " confirm
  case "${confirm:-Y}" in
    [Yy]*) ;;
    *) die "release aborted by user" ;;
  esac
fi

# ── Archive ──────────────────────────────────────────────────────────────────

log "archiving Release build..."
make archive APPLE_TEAM_ID="$TEAM_ID" DEVELOPER_ID_IDENTITY_SHA="$IDENTITY_SHA"

# ── Export ───────────────────────────────────────────────────────────────────

log "generating ExportOptions.plist..."
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>$SIGNING_IDENTITY</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
</dict>
</plist>
PLIST

log "exporting archive..."
make export-archive

# ── Locate exported app ─────────────────────────────────────────────────────

APP_PATH="$(find build/export -name "*.app" -maxdepth 3 -print -quit)"
[[ -d "$APP_PATH" ]] || die "exported app not found in build/export"
APP_NAME="$(basename "$APP_PATH")"
log "exported app: $APP_PATH"

# ── Re-sign Sparkle & Sentry frameworks ─────────────────────────────────────

log "re-signing embedded frameworks..."
SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"

if [[ -d "$SPARKLE" ]]; then
  codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp -v "$SPARKLE/XPCServices/Installer.xpc"
  codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp --preserve-metadata=entitlements -v "$SPARKLE/XPCServices/Downloader.xpc"
  codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp -v "$SPARKLE/Updater.app"
  codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp -v "$SPARKLE/Autoupdate"
  codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp -v "$SPARKLE/Sparkle"
  codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp -v "$APP_PATH/Contents/Frameworks/Sparkle.framework"
fi

SENTRY_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sentry.framework"
if [[ -d "$SENTRY_FRAMEWORK" ]]; then
  codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp -v "$SENTRY_FRAMEWORK/Versions/A/Sentry"
  codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp -v "$SENTRY_FRAMEWORK"
fi

# ── Re-sign bundled CLI ─────────────────────────────────────────────────────

PROWL_CLI="$APP_PATH/Contents/Resources/prowl-cli/prowl"
if [[ -f "$PROWL_CLI" ]]; then
  log "re-signing bundled prowl CLI with hardened runtime..."
  codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp -v "$PROWL_CLI"
fi

# ── Re-sign app ─────────────────────────────────────────────────────────────

log "re-signing app..."
codesign -f -s "$IDENTITY_SHA" -o runtime --timestamp --preserve-metadata=entitlements,requirements,flags -v "$APP_PATH"
codesign -vvv --deep --strict "$APP_PATH"
log "signature verified"

# ── DMG ──────────────────────────────────────────────────────────────────────

log "building DMG..."
DMG_PATH="build/Prowl.dmg"
mise exec -- create-dmg "$APP_PATH" build/ \
  --overwrite \
  --dmg-title="Prowl" \
  --identity="$IDENTITY_SHA"

DMG_OUTPUT="$(find build -name "*.dmg" -maxdepth 1 -newer build/ExportOptions.plist | head -1)"
if [[ "$DMG_OUTPUT" != "$DMG_PATH" ]] && [[ -n "$DMG_OUTPUT" ]]; then
  mv "$DMG_OUTPUT" "$DMG_PATH"
fi
[[ -f "$DMG_PATH" ]] || die "DMG not found at $DMG_PATH"

# ── Notarize ─────────────────────────────────────────────────────────────────

log "notarizing DMG..."
for attempt in 1 2 3; do
  if xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait; then
    break
  fi
  if [[ $attempt -lt 3 ]]; then
    log "notarization attempt $attempt failed, retrying in 30s..."
    sleep 30
  else
    die "notarization failed after 3 attempts"
  fi
done

log "stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler staple "$APP_PATH"

# ── Package zip for Sparkle ──────────────────────────────────────────────────

ZIP_PATH="build/Prowl.app.zip"
log "packaging $ZIP_PATH for Sparkle..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

# ── Appcast ──────────────────────────────────────────────────────────────────

log "generating appcast..."
STAGING="$(mktemp -d)"
ARCHIVE_BASE="$(basename "$ZIP_PATH" .zip)"
cp "$ZIP_PATH" "$STAGING/"
cp "$NOTES_FILE" "$STAGING/$ARCHIVE_BASE.md"

# Fetch existing appcast from the latest GitHub release for version history
curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" -o "$STAGING/appcast.xml" 2>/dev/null || true

"$PROJECT_DIR/bins/generate_appcast" \
  --ed-key-file "$SPARKLE_KEY_FILE" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --embed-release-notes \
  --maximum-versions 10 \
  "$STAGING"

cp "$STAGING/appcast.xml" build/appcast.xml
find "$STAGING" -name "*.delta" -exec cp {} build/ \; 2>/dev/null || true
rm -rf "$STAGING"
log "appcast generated at build/appcast.xml"

# ── Tag + push ───────────────────────────────────────────────────────────────

log "pushing tags..."
git push --follow-tags

# ── GitHub Release ───────────────────────────────────────────────────────────

log "creating GitHub Release..."
UPLOAD_FILES=("$DMG_PATH" "$ZIP_PATH" "build/appcast.xml")
DELTA_FILES=( $(find build -name "*.delta" -type f 2>/dev/null || true) )
UPLOAD_FILES+=("${DELTA_FILES[@]}")

# Delete existing release if present (idempotent re-run)
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  log "deleting existing release $TAG for re-creation..."
  gh release delete "$TAG" --repo "$REPO" --yes
fi

gh release create "$TAG" "${UPLOAD_FILES[@]}" \
  --repo "$REPO" \
  --title "Prowl $VERSION" \
  --notes-file "$NOTES_FILE"

RELEASE_URL="https://github.com/$REPO/releases/tag/$TAG"
log "release created: $RELEASE_URL"

# ── Trigger Prowl-Site rebuild ───────────────────────────────────────────────

log "triggering Prowl-Site rebuild..."
gh api repos/onevcat/Prowl-Site/dispatches \
  -f event_type=changelog-updated \
  -f "client_payload[version]=$VERSION" 2>/dev/null \
  && log "Prowl-Site rebuild triggered" \
  || log "Prowl-Site dispatch failed (non-critical)"

echo
log "done! Release: $RELEASE_URL"
