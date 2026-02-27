# Fork Sync and Personal Release Workflow

## Goal

Keep `onevcat/supacode` close to `supabitapp/supacode` while preserving local customizations (keybindings and feature trims), and make personal releases easy to produce and download from the fork Release page.

## Current Release Build in This Repo

The repository already has two production-grade workflows:

- `.github/workflows/release.yml`
  - Trigger: GitHub Release published.
  - Build: `make archive` + `make export-archive` on `macos-26`.
  - Packaging: app zip, dmg, Sparkle appcast, delta files.
  - Signing/notarization: required (Apple cert + notary credentials).
  - Publish target in workflow: hard-coded `supabitapp/supacode`.
- `.github/workflows/release-tip.yml`
  - Trigger: push to `main` (and manual dispatch).
  - Produces/updates `tip` prerelease assets and appcast.
  - Also requires signing/notarization secrets.

### Fork Impact

Out of the box, these workflows are not fork-friendly:

- They require many signing/secrets that forks usually do not have.
- Stable release publish target is hard-coded to upstream repo (`supabitapp/supacode`).
- Some appcast URLs are hard-coded to `supacode.sh`.

## Recommended Branch Strategy

- `upstream/main`: source of truth (read-only remote branch).
- `main` (origin): your integration branch with custom patches.
- `feat/onevcat-*`: optional short-lived branches per local customization.

## One-Time Setup

```bash
git fetch origin --prune
git fetch upstream --prune
git config rerere.enabled true
git config rerere.autoupdate true
```

`rerere` records your conflict resolutions so repeated upstream syncs become easier.

## Upstream Sync Runbook (Recommended: Merge)

```bash
git switch main
git fetch origin --prune
git fetch upstream --prune
git merge --ff-only origin/main
git merge --no-ff upstream/main
make build-app
make test
git push origin main
```

If conflicts happen, resolve once, commit, and `rerere` will likely auto-apply next time.

## Common Pitfalls and Fixes

- `git fetch origin upstream --prune` is invalid for this use case.
  `upstream` is interpreted as a refspec, which may fail with `fatal: couldn't find remote ref upstream`.
  Use two fetch commands (or `git fetch --all --prune`) instead.
- Prefer `git merge --ff-only origin/main` in scripted sync flow.
  It is deterministic and avoids `git pull` edge cases around `FETCH_HEAD`.
- Keep working tree clean before sync (`git status --short` should be empty), otherwise abort and stash/commit first.

## Personal Release Strategy (Fork Release Page)

The release helper now supports automatic notarization for personal fork releases.

Default flow:

1) Build app locally (`make build-app`).
2) Sign app with your `Developer ID Application` identity.
3) Notarize via `notarytool` and staple ticket to app.
4) Zip app bundle.
5) Create tag and upload zip to your fork GitHub Release page.

Non-notarized publishing is intentionally disabled for this fork.

## Helper Scripts

- Sync helper: `doc-onevcat/scripts/sync-upstream-main.sh`
- Release helper: `doc-onevcat/scripts/release-to-fork.sh`
  - Default target repo: auto-detected from `origin`
  - Override target repo: `GH_REPO=owner/repo`
  - Release create fallback: if `gh release create` fails (for example token scope mismatch), script falls back to `gh api` and then uploads assets
  - Notarization: mandatory (the script exits if `ENABLE_NOTARIZATION!=1`)
  - Default keychain profile name: `supacode-notary` (override with `APPLE_NOTARY_KEYCHAIN_PROFILE`)

### Example

```bash
# Sync upstream into local main and verify build
./doc-onevcat/scripts/sync-upstream-main.sh

# Create a personal release on fork release page
./doc-onevcat/scripts/release-to-fork.sh

# Or specify tag explicitly
./doc-onevcat/scripts/release-to-fork.sh onevcat-v2026.02.26-01
```

## Notarization Credentials

The script first tries `xcrun notarytool submit --keychain-profile <profile>`.
If profile is missing, it will create one using either:

- App Store Connect API key:
  - `APPLE_NOTARIZATION_KEY_PATH`
  - `APPLE_NOTARIZATION_KEY_ID`
  - `APPLE_NOTARIZATION_ISSUER`
- Or Apple ID credentials:
  - `APPLE_ID`
  - `APPLE_PASSWORD` (app-specific password)
  - `APPLE_TEAM_ID` (optional if inferable from signing identity)

Signing identity:

- `APPLE_SIGNING_IDENTITY` (optional). If omitted, script auto-detects the first available `Developer ID Application` identity from keychain.

## Optional: Full Signed Release on Fork

If you need notarized DMG and Sparkle feed in your fork:

- Copy/adjust release workflows to publish to `${{ github.repository }}`.
- Replace hard-coded download URL and release-notes URL with fork values.
- Configure all required secrets:
  - `DEVELOPER_ID_CERT_P12`
  - `DEVELOPER_ID_CERT_PASSWORD`
  - `DEVELOPER_ID_IDENTITY`
  - `KEYCHAIN_PASSWORD`
  - `APPLE_TEAM_ID`
  - `APPLE_NOTARIZATION_ISSUER`
  - `APPLE_NOTARIZATION_KEY_ID`
  - `APPLE_NOTARIZATION_KEY`
  - `SPARKLE_PRIVATE_KEY`
  - plus telemetry/sentry secrets used by workflow

For your current goal (personal periodic builds), the unsigned release helper is usually enough.
