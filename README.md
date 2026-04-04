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
make check                 # Run swiftformat and swiftlint
make test                  # Run app/unit tests (xcodebuild)
make build-cli             # Build `prowl` CLI via SwiftPM
make test-cli-smoke        # Quick CLI smoke checks
make test-cli-integration  # End-to-end CLI socket integration tests
make format                # Run swift-format
```

### Local Ghostty sync (avoid submodule/XCFramework drift)

```bash
make ensure-ghostty        # fast SHA check, rebuilds only when ThirdParty/ghostty changed
make sync-ghostty          # force rebuild + clear DerivedData
```

`build-app` and `test` already run `ensure-ghostty` automatically.

## Contributing

- I actual prefer a well written issue describing features/bugs u want rather than a vibe-coded PR
- I review every line personally and will close if I feel like the quality is not up to standard

