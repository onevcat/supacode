## Build Commands

```bash
open supacode.xcodeproj              # Open in Xcode (primary development)
make build-ghostty-xcframework       # Rebuild GhosttyKit from Zig source
make build-app                       # Build macOS app (Debug) via xcodebuild
make run-app                         # Build and launch Debug app
```

## Architecture

Supacode is a macOS orchestrator for running multiple coding agents in parallel, using GhosttyKit as the underlying terminal.

## Code Guidelines

See `./docs/swift-rules.md` for Swift/SwiftUI conventions. Key points:

## World class UX

- Buttons should have tooltip explains what it does, and the hotkey associated with it

## Rules

- After a task make sure the app builds properly.
- Use Peekabo skill to verify UI behavior if necessary.
- If you want to inspect a swift pm package, clone it to do so.

## References
- git@github.com:ghostty-org/ghostty.git - Dive into this codebase when needing to implement something with Ghostty
- git@github.com:khoi/git-wt.git - This is our repo, supacode uses this under the hood, we can change this if needed.
