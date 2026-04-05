# Changelog

## [2026.4.5](https://github.com/onevcat/Prowl/releases/tag/v2026.4.5) - 2026-04-05

This release introduces the `prowl` command-line tool, enabling scripted control of Prowl from the terminal.

### New

- **`prowl` CLI**: Control Prowl from the command line with `open`, `focus`, `send`, `read`, `list`, and `key` commands. Run `prowl --help` to get started.
- **Install the CLI from within the app**: Go to Settings > Advanced, the Prowl menu, or the Command Palette (Cmd+P) and choose "Install Command Line Tool" to add `prowl` to `/usr/local/bin`.
- **Auto-launch on `prowl open`**: If Prowl is not running when you invoke `prowl open <path>`, it launches automatically and then opens the requested path.
- **Auto-target resolution**: All selector commands (`focus`, `send`, `read`, `key`) now accept a positional `<target>` argument or `-t`/`--target` flag. Pass any pane UUID, tab UUID, or worktree name and Prowl resolves the type automatically.
- **`prowl send --capture`**: Snapshots the screen buffer before and after command execution and returns the diff as captured output, useful for scripted workflows that need to inspect command results.
- **Layout restore warning**: When a saved terminal layout snapshot cannot be restored, Prowl now shows a warning in the toolbar instead of silently resetting.

### Fixed

- Clicking anywhere on the Canvas row in the sidebar (including padding) now correctly selects Canvas. Previously only the icon and label text were responsive.
- Exiting Canvas could leave the terminal blank until you switched away and back. The surface state is now refreshed immediately on Canvas exit.

## [2026.4.2](https://github.com/onevcat/Prowl/releases/tag/v2026.4.2) - 2026-04-01

This release brings two headline features: fully customizable keyboard shortcuts and persistent terminal layout across app launches, so Prowl adapts to your workflow instead of the other way around.

### New

- **Fully customizable keyboard shortcuts**: A dedicated Shortcuts page in Settings gives you complete control over every key binding in Prowl. Remap app actions, terminal tab and pane navigation, split management, and the command palette to any key combination you prefer. The editor records shortcuts directly from your keyboard, detects conflicts with existing bindings inline, and lets you replace or cancel on the spot. Whether you are a Vim user remapping splits or just want `Cmd+T` to do something different, every shortcut is now yours to define.
- **Terminal layout restore**: Prowl now remembers your full terminal layout — tabs, splits, and their arrangement — and restores it exactly when you relaunch. Enable "Restore Layout on Launch" in Settings > Advanced, and your workspace is back in seconds, no matter how complex the setup. Use "Clear saved terminal layout" to reset to the default empty state whenever you want a fresh start.
- **Custom commands revamp**: The repository custom commands editor is now a fully inline-editable table with an SF Symbol icon picker, shortcut recording, and no cap on the number of commands. Commands beyond the first three appear in a toolbar overflow menu.
- **Script environment variables**: Scripts run by Prowl now receive `PROWL_WORKTREE_PATH` and `PROWL_ROOT_PATH` environment variables (renamed from the old `SUPACODE_` prefix).
- **Window menu additions**: Tab and pane selection shortcuts are now accessible from the Window menu.

### Fixed

- Font size no longer resets when switching between worktrees or when Ghostty reloads its config due to custom command changes.
- `Cmd+0` (reset font size) now affects the current pane only; new tabs inherit the reset size. The old tab-0 and worktree-0 shortcuts (`Cmd+0` / `Ctrl+0`) have been removed to free up these key combinations.
- Terminal layout restore now works correctly for plain folders and correctly suppresses re-saving after clicking "Clear saved terminal layout."
- Pane focus is correctly restored after toggling zoom on a split pane.
- Scripts running in fish shell no longer hang due to an `exit $?` incompatibility.

## [2026.3.28](https://github.com/onevcat/Prowl/releases/tag/v2026.3.28) - 2026-03-27

### New

- Terminal font size now persists across sessions. Prowl saves your preferred size and restores it when you relaunch. Font size controls are available in the View menu.
- Cmd+0 has been freed from its previous font-size binding, making it available for custom Ghostty keybindings.

### Fixed

- Plain folder repositories now show the correct open tab count in the sidebar header.

## [2026.3.27](https://github.com/onevcat/Prowl/releases/tag/v2026.3.27) - 2026-03-26

### New

- The sidebar now shows a small tab count badge next to each repository name, reflecting the total number of open terminal tabs across all worktrees for that repo. The badge appears automatically when tabs are open and disappears when none remain.
- Prowl is now available via Homebrew: `brew install --cask onevcat/tap/prowl`. Updates are also delivered through the tap automatically.

## [2026.3.25](https://github.com/onevcat/Prowl/releases/tag/v2026.3.25) - 2026-03-25

This release adds Canvas multi-select broadcast input — select multiple terminal cards and type once to send the same input to all of them.

- Canvas multi-select: Cmd+Click to select multiple cards, Cmd+Opt+A to select all. Selected cards show a visual distinction between primary (accent ring) and followers (subtle tint).
- Broadcast input: typing in the primary card mirrors committed text and special keys (Enter, Backspace, arrows, Tab, Escape, Ctrl+key) to all selected follower cards.
- IME-safe broadcast: followers receive only committed text (e.g. 你好), not intermediate phonetic input (e.g. nihao). Works correctly with Chinese, Japanese, and other input methods.
- Cmd+V paste and right-click Paste are broadcast to all selected cards.
- Cmd+Backspace (delete line) and Cmd+Arrow (line navigation) are broadcast to followers.
- Escape clears broadcast selection. Click a follower to promote it to primary without clearing selection.
- Fixed: terminal scrollback position is now preserved during output, preventing unwanted scroll jumps.
- Fixed: Cmd+W now correctly closes the focused surface in Canvas mode.

## [2026.3.24](https://github.com/onevcat/Prowl/releases/tag/v2026.3.24) - 2026-03-24

This release introduces plain folder support and includes several UX and stability improvements.

- Plain folders can now be added alongside Git repositories. They open directly into terminal tabs with their own toolbar, settings, and command palette entries. Git-only actions are hidden when a plain folder is selected. Folders are automatically upgraded to Git repositories when a `.git` directory is detected, and conservatively downgraded when it is removed.
- Hotkey actions for archive and delete worktree are now scoped to the sidebar, preventing accidental triggers from the terminal. Close Window (⌘W) now works when no terminal is focused, and Show Window (⌘0) brings the main window to front.
- Fixed: exiting Canvas could leave terminal surfaces blank. Occlusion state is now correctly restored whenever a surface is reattached, regardless of how the transition happened.
- App size reduced by approximately 7 MB thanks to an optimized YiTong web bundle.
- Fixed: the Settings toolbar no longer shows an unnecessary separator on macOS 26.
- Added diagnostic logging for scroll jump events to help investigate an intermittent snap-to-bottom issue during scrollback reading.

## [2026.3.23](https://github.com/onevcat/Prowl/releases/tag/v2026.3.23) - 2026-03-23

- Double-click a card's title bar in Canvas to switch directly to that tab's normal view. First click focuses the card with immediate visual feedback, second click switches the view.
- Canvas Arrange and Organize now animate smoothly when repositioning cards.
- Fixed blank terminal surface when exiting Canvas via the toggle shortcut.

## [2026.3.22](https://github.com/onevcat/Prowl/releases/tag/v2026.3.22) - 2026-03-22

- Command finished notifications now alert you when a long-running terminal command completes. Configure the duration threshold in Settings.
- In Canvas, unseen notifications now highlight the entire title bar of the affected tab card, tracked per-tab for better granularity.
- Notifications are automatically marked as read when you type into the focused terminal, and command finished notifications are suppressed if you've recently interacted with that terminal.
- Fixed: worktree selection is now cleared when entering Canvas mode, preventing stale focus state.
- Terminal key repeat now works immediately — the macOS press-and-hold accent menu is disabled in terminal surfaces.
- Updated the embedded terminal engine to Ghostty v1.3.1.
- VSCodium is now recognized as a supported editor.

## [2026.3.21](https://github.com/onevcat/Prowl/releases/tag/v2026.3.21) - 2026-03-21

This release wires up several Ghostty keybindings and actions that previously had no effect in Prowl.

- You can now rename a tab or terminal surface title from the command palette or a bound key. "Change Tab Title" locks the title until you clear it; "Change Terminal Title" sets the surface title and resumes auto-updates when cleared.
- "Open Config" now opens your Ghostty configuration file in the default text editor.
- Fullscreen (`toggle_fullscreen`), maximize (`toggle_maximize`), and background opacity (`toggle_background_opacity`) Ghostty actions now work as expected. Opacity toggling requires `background-opacity < 1` in your Ghostty config and has no effect in fullscreen.
- The `quit` action now routes through the standard macOS termination flow, so any confirm-before-quit prompt still triggers. `close_window` closes the window containing the active terminal.
- Fixed: The command palette no longer shows duplicate or inapplicable entries (removed redundant "Check for Updates", single-window actions like "New Window", Ghostty debug tools, and iOS-only actions).

## [2026.3.20](https://github.com/onevcat/Prowl/releases/tag/v2026.3.20) - 2026-03-20

Startup is faster and more reliable in this release.

- Repositories now appear immediately on launch by restoring from a local snapshot cache, rather than waiting for the full live refresh to complete. The cache is stored at `~/.prowl/repository-snapshot.json` and is always followed by a background refresh to stay up to date.
- Worktree discovery now runs in parallel across all repositories, and the bundled `wt` tool is invoked directly instead of through a login shell, reducing startup latency.
- Fixed: Prowl no longer deletes `~/.supacode` on first launch when co-installed with Supacode. Migration now copies data to `~/.prowl` instead of moving it.

## [2026.3.19](https://github.com/onevcat/Prowl/releases/tag/v2026.3.19) - 2026-03-19

This release focuses on Canvas improvements: better card layout, smarter focus behavior, and a keyboard shortcut to toggle the view.

- Press `⌥⌘↩` to toggle Canvas view. The command has also moved to the View menu.
- Canvas now auto-arranges cards on first entry using a masonry-style packing algorithm, which produces a more compact, better-scaled layout.
- When entering Canvas, focus automatically returns to the card you were last working on. When exiting, focus restores to the exact worktree and tab you had active inside Canvas.
- Fixed: file paths containing Unicode characters (e.g., Chinese filenames) were not shown correctly in diffs and untracked file lists.
- Added notification settings for focus events, allowing you to control when Prowl alerts you about focus changes.

## [2026.3.18.2](https://github.com/onevcat/Prowl/releases/tag/v2026.3.18.2) - 2026-03-18

Canvas receives layout and polish improvements in this release.

- Added an "Arrange" button to the Canvas toolbar that automatically lays out cards in a waterfall pattern, making it easy to tidy up a crowded canvas.
- Increased the default card size and raised the maximum resize limit, giving more room to work with agent output at a glance.
- Fixed: the Canvas toolbar title no longer appears as a tappable navigation button.
- Fixed: the Canvas sidebar button label is now properly centered, and no longer bleeds through overlapping content when scrolling.

## [2026.3.18](https://github.com/onevcat/Prowl/releases/tag/v2026.3.18) - 2026-03-18

Initial public release of Prowl, rebranded from Supacode.

- Prowl is now the app's name and identity, with an updated app icon to match.
- Sparkle auto-update support is included, so future releases will be delivered automatically.
