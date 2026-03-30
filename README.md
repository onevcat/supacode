# Prowl

Native terminal coding agents command center. Fork of [Supacode](https://github.com/supabitapp/supacode).

## Technical Stack

- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)
- [libghostty](https://github.com/ghostty-org/ghostty)

## Requirements

- macOS 26.0+
- [mise](https://mise.jdx.dev/) (for dependencies)

## Building

```bash
make build-ghostty-xcframework   # Build GhosttyKit from Zig source
make build-app                   # Build macOS app (Debug)
make run-app                     # Build and launch
```

## Development

```bash
make check     # Run swiftformat and swiftlint
make test      # Run tests
make format    # Run swift-format
```

## Command Line (open-path entry)

Prowl now ships a first-class CLI entry script at `bin/prowl`.

```bash
bin/prowl
bin/prowl ~/Downloads
bin/prowl .
bin/prowl open ~/Projects/Prowl
```

Argument routing rules:
- Reserved subcommands go to subcommand routing: `help version open list focus send key read`
- Path-like first arguments route to open-path: `/...`, `./...`, `../...`, `~/...`, `file://...`, `.`, `..`
- Other first arguments fail with usage error

Current scope of this entrypoint is open-path (`prowl`, `prowl <path>`, `prowl open <path>`). The other reserved subcommands are intentionally reserved for upcoming first-class implementations.

## Contributing

- I actual prefer a well written issue describing features/bugs u want rather than a vibe-coded PR
- I review every line personally and will close if I feel like the quality is not up to standard

