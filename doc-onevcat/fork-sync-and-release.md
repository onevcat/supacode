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
git fetch origin upstream --prune
git config rerere.enabled true
git config rerere.autoupdate true
```

`rerere` records your conflict resolutions so repeated upstream syncs become easier.

## Upstream Sync Runbook (Recommended: Merge)

```bash
git switch main
git fetch origin upstream --prune
git pull --ff-only origin main
git merge --no-ff upstream/main
make build-app
make test
git push origin main
```

If conflicts happen, resolve once, commit, and `rerere` will likely auto-apply next time.

## Personal Release Strategy (Fork Release Page)

For personal usage, the easiest path is:

1) Build unsigned Debug app locally (`make build-app`).
2) Zip app bundle.
3) Create a tag.
4) Upload zip to your fork GitHub Release page.

This avoids Apple signing/notarization setup and keeps the workflow simple.

## Helper Scripts

- Sync helper: `doc-onevcat/scripts/sync-upstream-main.sh`
- Release helper: `doc-onevcat/scripts/release-to-fork.sh`

### Example

```bash
# Sync upstream into local main and verify build
./doc-onevcat/scripts/sync-upstream-main.sh

# Create a personal release on fork release page
./doc-onevcat/scripts/release-to-fork.sh

# Or specify tag explicitly
./doc-onevcat/scripts/release-to-fork.sh onevcat-v2026.02.26-01
```

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
