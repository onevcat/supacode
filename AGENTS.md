## Build Commands

```bash
make build-ghostty-xcframework  # Rebuild GhosttyKit from Zig source (requires mise)
make build-app                   # Build macOS app (Debug) via xcodebuild
make run-app                     # Build and launch Debug app
make check                        # Run swiftformat and swiftlint
make test                        # Run all tests
make bump-version                # Bump patch version and create git tag
make bump-and-release            # Bump version and push to trigger release
```

## Architecture

Supacode is a macOS orchestrator for running multiple coding agents in parallel, using GhosttyKit as the underlying terminal.

### Core Data Flow

```
AppFeature (root TCA store)
├─ RepositoriesFeature (repos + worktrees)
├─ WorktreeInfoFeature (PR/CI status display)
├─ SettingsFeature (appearance, updates, repo settings)
└─ UpdatesFeature (Sparkle auto-updates)

WorktreeTerminalManager (global @Observable terminal state)
├─ selectedWorktreeID (tracks current selection for bell logic)
└─ WorktreeTerminalState (per worktree)
    └─ TerminalTabManager (tab/split management)
        └─ GhosttySurfaceState[] (one per terminal surface)

GhosttyRuntime (shared singleton)
└─ ghostty_app_t (single C instance)
    └─ ghostty_surface_t[] (independent terminal sessions)
```

### Source Layout

```
supacode/
├─ App/                 # Entry point, shortcuts, ContentView
├─ Domain/              # Core models: Repository, Worktree, OpenWorktreeAction
├─ Features/
│  ├─ App/              # AppFeature (root TCA reducer)
│  ├─ Repositories/     # Sidebar views and RepositoriesFeature reducer
│  ├─ RepositorySettings/ # Per-repo settings feature
│  ├─ Settings/         # Global settings views, models, reducer
│  ├─ Terminal/         # Tab bar, split views, WorktreeTerminalManager
│  ├─ Updates/          # Sparkle update feature
│  └─ WorktreeInfo/     # PR/CI status panel
├─ Clients/             # TCA dependency clients
│  ├─ Git/              # GitClient (shells out to bundled wt script)
│  ├─ Github/           # GithubCLIClient (gh CLI wrapper)
│  ├─ Shell/            # ShellClient for process execution
│  └─ ...               # Terminal, Workspace, Settings clients
├─ Infrastructure/
│  └─ Ghostty/          # Runtime, SurfaceView, SurfaceBridge, ShortcutManager
├─ Commands/            # macOS menu command handlers
└─ Support/             # Utilities: SupacodePaths, GlobalConstants
```

### Key Dependencies

- **TCA (swift-composable-architecture)**: App state, reducers, side effects
- **GhosttyKit**: Terminal emulator (built from Zig source in ThirdParty/ghostty)
- **Sparkle**: Auto-update framework
- **swift-dependencies**: Dependency injection for TCA clients

### TCA ↔ Terminal Communication

The terminal layer (`WorktreeTerminalManager`) is `@Observable` but outside TCA. Communication uses `TerminalClient`:

```
Reducer → terminalClient.send(Command) → WorktreeTerminalManager
                                                    ↓
Reducer ← .terminalEvent(Event) ← AsyncStream<Event>
```

- **Commands**: `createTab`, `closeFocusedTab`, `prune`, `setSelectedWorktreeID`, etc.
- **Events**: `notificationReceived`, `tabCreated`, `tabClosed`, `focusChanged`, `taskStatusChanged`
- Wired in `supacodeApp.swift`, subscribed in `AppFeature.task`

## Ghostty Keybindings Handling

- Ghostty keybindings are handled via runtime action callbacks in `GhosttySurfaceBridge`, not by app menu shortcuts.
- App-level tab actions should be triggered by Ghostty actions (`GHOSTTY_ACTION_NEW_TAB` / `GHOSTTY_ACTION_CLOSE_TAB`) to honor user custom bindings.
- `GhosttySurfaceView.performKeyEquivalent` routes bound keys to Ghostty first; only unbound keys fall through to the app.

## Code Guidelines

Always read `./docs/swift-rules.md` before writing Swift code. Key points:
- Target macOS 26.0+, Swift 6.2+
- Use `@ObservableState` for TCA feature state; use `@Observable` for non-TCA shared stores; never `ObservableObject`
- Always mark `@Observable` classes with `@MainActor`
- Modern SwiftUI only: `foregroundStyle()`, `NavigationStack`, `Button` over `onTapGesture()`
- Prefer Swift-native APIs over Foundation where they exist (e.g., `replacing()` not `replacingOccurrences()`)
- Avoid `GeometryReader` when `containerRelativeFrame()` or `visualEffect()` would work
- Do not use NSNotification to communicate between reducers.

## UX Standards

- Buttons must have tooltips explaining the action and associated hotkey
- Use Dynamic Type, avoid hardcoded font sizes
- Components should be layout-agnostic (parents control layout, children control appearance)
- Never use custom colors, always use system provided ones.
- We use `.monospaced()` modifier on fonts when apprpropriate

## Rules

- After a task, ensure the app builds: `make build-app`
- Use Peekaboo skill to verify UI behavior if necessary
- To inspect a Swift PM package, clone it with `gj get {git_url}`
- Automatically commit your changes and your changes only. Do not use `git add .`
- Never mention competitors or other apps in commits or PRs
- Before you go on your task, check the current git branch name, if it's something generic like an animal name, name it accordingly. Do not do this for main branch
- After implementing an execplan, always submit a PR if you're not in the main branch

## Ghostty

When following/porting Ghostty logic from their macOS app, try to match the implementation exactly, no smartness, no corner cutting. 

## References

- `git@github.com:ghostty-org/ghostty.git` - Dive into this codebase when implementing Ghostty features
- `git@github.com:khoi/git-wt.git` - Bundled git worktree wrapper (in Resources/git-wt/wt), modified in the repo directly, do not modified the bundled script we have
