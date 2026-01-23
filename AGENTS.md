## Build Commands

```bash
open supacode.xcodeproj              # Open in Xcode (primary development)
make build-ghostty-xcframework       # Rebuild GhosttyKit from Zig source (requires mise)
make build-app                       # Build macOS app (Debug) via xcodebuild
make run-app                         # Build and launch Debug app
make lint                            # Run swiftlint
make test                            # Run tests
make format                          # Run swift-format
```

## Architecture

Supacode is a macOS orchestrator for running multiple coding agents in parallel, using GhosttyKit as the underlying terminal.

### Core Data Flow

```
RepositoryStore (central state)
  └─ Repository[] (git repos with worktrees)
      └─ Worktree[] (each branch = independent workspace)

WorktreeTerminalStore (global terminal state)
  └─ WorktreeTerminalState (per worktree)
      └─ BonsplitController (tab/pane management)
          └─ GhosttySurfaceView[] (one per terminal tab)

GhosttyRuntime (shared singleton)
  └─ ghostty_app_t (single C instance)
      └─ ghostty_surface_t[] (independent terminal sessions)
```

### Key Components

- **GhosttyEmbed/**: Ghostty C API integration - `GhosttyRuntime` initializes the shared instance, `GhosttySurfaceView` handles rendering/input per terminal
- **Terminals/**: Terminal UI layer using Bonsplit for tab management
- **RepositoryStore.swift**: Central state management for repos and worktrees
- **GitClient.swift**: Git CLI wrapper for worktree operations (uses bundled `git-wt` script)
- **Commands/**: macOS menu command handlers (worktree, terminal, sidebar)

### State Management Pattern

All `@Observable` classes use `@MainActor` isolation (Swift 6 strict concurrency). Key stores: `RepositoryStore`, `WorktreeTerminalStore`, `GhosttyTerminalStore`, `SettingsModel`.

## Ghostty Keybindings Handling

- Ghostty keybindings are handled via runtime action callbacks in `GhosttySurfaceBridge`, not by app menu shortcuts.
- App-level tab actions should be triggered by Ghostty actions (`GHOSTTY_ACTION_NEW_TAB` / `GHOSTTY_ACTION_CLOSE_TAB`) to honor user custom bindings.
- `GhosttySurfaceView.performKeyEquivalent` routes bound keys to Ghostty first; only unbound keys fall through to the app.

## Code Guidelines

Always read `./docs/swift-rules.md` before writing Swift code. Key points:
- Target macOS 26.0+, Swift 6.2+
- Use `@Observable` with `@MainActor`, never `ObservableObject`
- Modern SwiftUI only: `foregroundStyle()`, `NavigationStack`, `Button` over `onTapGesture()`
- Prefer Swift-native APIs over Foundation where they exist

## UX Standards

- Buttons must have tooltips explaining the action and associated hotkey
- Use Dynamic Type, avoid hardcoded font sizes
- Components should be layout-agnostic (parents control layout, children control appearance)

## Rules

- After a task, ensure the app builds: `make build-app`
- Use Peekabo skill to verify UI behavior if necessary
- To inspect a Swift PM package, clone it with `gj get {git_url}`

## Releases

- When making new releases use `make bump-version` (auto-increments minor) or `make bump-version VERSION=x.x.x`
- Tagging `vx.x.x` and push will trigger prod build automatically by Github action

## References

- `git@github.com:ghostty-org/ghostty.git` - Dive into this codebase when implementing Ghostty features
- `git@github.com:khoi/git-wt.git` - Our git worktree wrapper, can be modified as needed
- `git@github.com:vivy-company/aizen.git` - A competitor, also use ghostty
