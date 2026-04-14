# Fork Change Log

## Upstream Baseline

| Key | Value |
| --- | --- |
| Commit | `0150ceaf0d2bc5e976df25b2f2cfa33ad92e5558` |
| Tag | v0.8.0 |
| Date | 2026-04-08 |

All upstream changes up to and including this commit have been reviewed.
Future upstream checks should only inspect commits **after** this baseline.

---

## 2026-04-08 — Full upstream review & change-list format migration

### Upstream changes reviewed

Reviewed all upstream (`supabitapp/supacode`) commits from our last sync through `0150ceaf` (v0.8.0). Key additions:

- **Deeplinks** (`a7f6d81f`) — new deeplink handling
- **Coding agent hook system** (`61356be1`) — hooks for Claude Code and Codex
- **Auto-hide tab bar for tmux** (`dc8eb02e`) — new setting
- **Inhibit command on script & single-tab bar hiding** (`301cf398`)
- **Auto-delete archived worktrees** (`666d440d`) — configurable retention period
- **Terminal layout persistence and restoration** (`771e4aab`)
- **Global worktree settings** (`c29ee5a5`) — global defaults with per-repo overrides
- **Merged worktree action picker** (`4db25220`) — replaces auto-archive toggle
- **Global defaults for copy flags and merge strategy** (`ce214902`) — overlaps with our #178

### Decisions

- **#178 (global defaults)**: Upstream added `ce214902` which covers global defaults for copy flags and merge strategy. Our fork branch `feat/issue-178-global-defaults` (`c7a10bd0`) implements the same concept. On next upstream sync, check for conflicts and prefer upstream's implementation where equivalent; keep fork extensions if any.
- **#173, #177**: Both PRs already merged.
- **change-list.md format**: This file is no longer maintained as a per-commit tracking table. It is now a dated log of upstream reviews and fork decisions. Use the `/check-upstream-changes` command to generate diffs against the baseline.

---

## Old Log

The table below was the original per-commit tracking format, preserved for reference.

| summary | commit hash | status |
| --- | --- | --- |
| Fix initial prompt path by normalizing trailing slash so working directory is set correctly on launch. | `fbfeec4` | Merged upstream |
| Align embedded Ghostty accessibility with Ghostty.app so AX-driven dictation/transcription tools like Typeless can recognize terminal panes correctly. | `aa57f08` | Merged upstream |
| Add fork sync and personal release workflow docs plus helper scripts (`sync-upstream-main.sh`, `release-to-fork.sh`). | `3599f5f` | Fork only |
| Remove `Cmd+Delete` shortcut from worktree archive actions, so the key can be handled by Ghostty/terminal behavior. | `022bb87` | Fork only |
| Harden fork release script: detect target repo from `origin` and add fallback (`gh api` + upload) when `gh release create` fails. | `058177e` | Fork only |
| Add local app notarization flow to fork release script (Developer ID signing + `notarytool` + stapling) for personal releases. | `a66c4b2` | Fork only |
| Clarify fork customization guidance and release workflow docs for this fork. | `b7f4e0b` | Fork only |
| Ignore local build artifacts in fork working tree to reduce noise. | `cccd36d` | Fork only |
| Harden upstream sync script/docs with deterministic fetch/merge flow and safer failure handling. | `56deb49` | Fork only |
| Add repo-scoped custom command buttons with configurable icon/title/command/execution mode and shortcut overrides. | `76046bc` | Fork only |
| Refine custom shortcut editor layout by tightening modifier symbol and toggle spacing. | `b5c58e4` | Fork only |
| Execute Terminal Input custom commands by injecting return key so the command runs immediately. | `562042f` | Fork only |
| Disable push-triggered `tip` release workflow in fork to avoid expected CI failures. | `85b3fd7` | Fork only |
| Enforce notarized-only fork releases; block non-notarized publishing path in release script and docs. | `2ab70fd` | Fork only |
| Move repo-scoped settings files to `~/.prowl/repo/<repo-last-path>/` (was `~/.supacode/repo/…`) with legacy migration from repo root files. | `ea9259f` | Fork only |
| Add `/fork-release` slash command for upstream sync and private release workflow. | `64829dc` | Fork only |
| Add diff window with file tree sidebar and YiTong DiffView for viewing worktree changes. | `0d03848`, `09194c4` | Fork only |
| Wire up diff badge click in worktree row, `Cmd+]` shortcut, and Show Diff menu item. | `59dc4f6` | Fork only |
| Preload all file contents on diff window open for instant file switching. | `5850576` | Fork only |
| Add toolbar with sidebar toggle, diff style picker (split/unified), `Cmd+W` close, and window frame persistence. | `8985fc2` | Fork only |
| Add Canvas (Live Sessions) feature: free-form view displaying all open tabs as draggable, resizable cards in a balanced grid layout with pinch-to-zoom (cursor-anchored), two-finger scroll panning, organize button, and fit-to-view on open. | `2c1d9aa`…`80df1b1` | Fork only |
| Render full split pane layout in Canvas cards with `pinnedSize` propagation through the split tree to prevent terminal reflow during zoom. Enable resize handles on all four edges and corners. | `12496d5` | Fork only |
| Show all open tabs (not just active) as separate cards in Canvas; per-tab layout, focus, resize, and occlusion management. | `e5992ea` | Fork only |
| Fix Canvas grid layout: batch positioning to avoid overlap, stale layout cleanup, and organize/fit-to-view helpers. | `80df1b1`, `2653c06` | Fork only |
| Add two-finger scroll to pan canvas via NSView scroll-wheel interception. | `2738c24` | Fork only |
| Fix canvas pinch-to-zoom to anchor on cursor position instead of origin. | `c24e092` | Fork only |
| Add PreToolUse hook to block `gh pr create` targeting upstream; PRs must explicitly target fork. | `9970560` | Fork only |
| Add PR target rule to CLAUDE.md: always target `onevcat/supacode`, never upstream. | `962ba62` | Fork only |
| Rebrand user-facing identity from Supacode to Prowl: app name, icon, bundle display name, settings file paths (`prowl.json`), subsystem identifiers, and about/UI strings. Keep module name as `supacode` for code compatibility. | `5f7d84a`…`5676418` | Fork only |
| Add public release infrastructure: Sparkle EdDSA key setup, date-based version scheme (`YYYY.M.DD`), full release script with DMG/notarization/appcast, `install-release` Makefile target, `/release` and `/sync-upstream` commands. | — | Fork only |
| Parallelize repository startup loading to speed up launch with many repos. | `8dd8eac` | Merged upstream |
| Run bundled `wt` binary directly instead of shell discovery for faster worktree operations. | `ed27b31` | Merged upstream |
| Evolve Canvas card layout algorithm (waterfall → MaxRects → combined row-break + waterfall packing) for better space utilization; auto-arrange cards on first Canvas entry per session; improved fit-to-view scaling. | `15bafd1`…`fc81375` | Fork only |
| Add Canvas toggle shortcut; auto-focus the previously active card when entering Canvas; exit Canvas to the focused worktree+tab; move Canvas and Show Diff to View menu. | `38a6361`, `3c4dc3c`, `17df275`, `d9dde25` | Fork only |
| Implement Ghostty `prompt-title` and `open-config` callbacks: surface prompts update tab titles; open-config opens Ghostty config in default text editor. | `2b55336`…`1352165` | Fork only |
| Route Ghostty window actions (`toggle_fullscreen`, `toggle_maximize`, `toggle_background_opacity`, `quit`, `close_window`) through Prowl; quit goes through TCA `requestQuit` for confirm-before-quit. | `5ca2bf4`…`4732780` | Fork only |
| Filter duplicate and unsupported Ghostty actions from command palette. | `512c5b3`, `c8c562f` | Fork only |
| Add command finished notification for long-running terminal commands with configurable duration threshold; Canvas highlights the entire title bar for unseen notifications, tracked per-tab. | `182e165`…`d7bb4b6` | Fork only |
| Mark notifications as read on key input to focused terminal surface; suppress command finished notification after recent user interaction. | `26968c1`, `2db9ae5` | Fork only |
| Add repository snapshot startup cache to skip full git scan on re-launch when worktrees haven't changed. | `7136591` | Pending upstream (#162) |
| Fix unicode paths in diff and untracked file output. | `1b32a26` | Fork only |
| Fix settings migration to copy instead of move, preserving `~/.supacode` for upstream compatibility. | `07121b6` | Fork only |
| Use Claude to generate user-facing release notes; skip generation when pre-written notes exist. | `64d0928`, `849b5cf` | Fork only |
| Remove CI release workflows (`release.yml`, `release-tip.yml`) and make tip update channel equivalent to stable; releases are now handled locally via `/release` skill. | `7f79078`, `4546b66` | Fork only |
