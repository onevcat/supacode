---
name: release
description: Build, sign, notarize, and publish a Prowl release.
---

# Release

Build, sign, notarize, and publish a Prowl release.

1. Verify current branch is `main`: `git branch --show-current`
   - If not on main, abort and tell the user to switch first
2. Verify working tree is clean: `git status --porcelain`
   - If dirty, list the changes and ask whether to proceed or abort
3. Determine the version:
   - If `$ARGUMENTS` is provided, use it as the version (e.g., `2026.3.18`)
   - Otherwise, default to today's date format and confirm with the user before proceeding
4. Generate release notes: `./doc-onevcat/scripts/release-notes.sh <VERSION>`
   - This script compares HEAD against the previous release tag, gathers commits and
     PR descriptions, and generates user-facing notes via LLM into `build/release-notes.md`.
   - Read the generated `build/release-notes.md`, show the content to the user, and wait
     for explicit confirmation. If the user wants changes, edit the file directly.
   - **Do NOT proceed to the next step until the user confirms the release notes.**
5. Run the release script: `./doc-onevcat/scripts/release.sh <VERSION>`
   - The script reads `build/release-notes.md` (required — refuses to run without it).
   - It handles: version bump, build, sign, notarize, DMG, appcast, GitHub Release, and
     Prowl-Site update. If the tag already exists (e.g., from a prior interrupted run),
     it skips the bump step automatically.
6. Report the GitHub release URL and remind the user to verify:
   - The DMG downloads and installs correctly
   - Sparkle update check works (launch app → Check for Updates)
   - The appcast at `https://prowl.onev.cat/appcast.xml` is updated
