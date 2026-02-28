### Change content

| summary | commit hash |
| --- | --- |
| Align embedded Ghostty accessibility with Ghostty.app so AX-driven dictation/transcription tools like Typeless can recognize terminal panes correctly. | `aa57f08` |
| Add fork sync and personal release workflow docs plus helper scripts (`sync-upstream-main.sh`, `release-to-fork.sh`). | `3599f5f` |
| Remove `Cmd+Delete` shortcut from worktree archive actions, so the key can be handled by Ghostty/terminal behavior. | `022bb87` |
| Harden fork release script: detect target repo from `origin` and add fallback (`gh api` + upload) when `gh release create` fails. | `058177e` |
| Add local app notarization flow to fork release script (Developer ID signing + `notarytool` + stapling) for personal releases. | `a66c4b2` |
| Clarify fork customization guidance and release workflow docs for this fork. | `b7f4e0b` |
| Ignore local build artifacts in fork working tree to reduce noise. | `cccd36d` |
| Harden upstream sync script/docs with deterministic fetch/merge flow and safer failure handling. | `56deb49` |
| Add repo-scoped custom command buttons with configurable icon/title/command/execution mode and shortcut overrides. | `76046bc` |
| Refine custom shortcut editor layout by tightening modifier symbol and toggle spacing. | `b5c58e4` |
| Execute Terminal Input custom commands by injecting return key so the command runs immediately. | `562042f` |
| Disable push-triggered `tip` release workflow in fork to avoid expected CI failures. | `85b3fd7` |
| Enforce notarized-only fork releases; block non-notarized publishing path in release script and docs. | `2ab70fd` |
| Move repo-scoped settings files to `~/.supacode/repo/<repo-last-path>/` with legacy migration from repo root files. | `ea9259f` |
