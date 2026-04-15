<p align="center">
  <img src="https://prowl.onev.cat/images/prowl-icon-rounded.png" width="128" alt="Prowl">
</p>

<h1 align="center">Prowl</h1>

<p align="center">
  <b>Your terminal wasn't built for agents. Until now.</b><br>
  A native macOS command center for running AI coding agents in parallel.
</p>

<p align="center">
  <a href="https://github.com/onevcat/Prowl/releases/latest/download/Prowl.dmg"><b>Download</b></a>
  ·
  <a href="https://prowl.onev.cat">Website</a>
  ·
  <code>brew install --cask onevcat/tap/prowl</code>
</p>

<p align="center">
  <img src="https://prowl.onev.cat/images/promotion.webp" alt="Prowl — vertical tabs, terminals, command palette, and split view">
</p>

---

## Why Prowl?

You're not just typing commands anymore — you're orchestrating Claude Code, Codex, and friends across repos, branches, and ideas. Prowl is the terminal built for that.

## Highlights

### 🖼 Canvas — every agent, at a glance

<img align="right" width="360" src="https://prowl.onev.cat/images/feature-canvas.png" alt="Canvas view of multiple live agent terminals">

Three agents running, one just finished — _where_? Canvas gives you a bird's-eye view where every card is a **live, interactive terminal**, not a screenshot. Finished tasks light up the moment they complete, and you can broadcast a single command to every agent at once.

<br clear="all">

### ⚡ Custom Actions — one keystroke, any workflow

<img align="right" width="360" src="https://prowl.onev.cat/images/feature-custom-actions.png" alt="Custom Actions with per-repo buttons and shortcuts">

Pin `swift build`, `npm test`, or `claude -p "review this diff"` to a button and bind it to `⌘B`. Set it up once per repo and stop typing the same thing every day. Pair with `claude -p` / `codex exec` to turn your terminal into a daily AI-powered assistant.

<br clear="all">

### 🤖 CLI — let your agents drive the terminal

Your agent needs to run a test, read the output, and decide what's next. Prowl ships with a `prowl` CLI so both you and your agents can control the terminal programmatically:

```bash
prowl list                         # discover panes & their status
prowl send "npm test" --capture    # execute & capture output in one shot
prowl read                         # read screen content on demand
prowl key <keystroke>              # send keystrokes programmatically
```

### And the stuff you'd expect, done right

- **Full Native** — powered by libghostty. No Electron, no web views. CJK-safe out of the box.
- **Vertical Tabs** — repos, branches, and worktrees in a sidebar. Never lose context.
- **Git Worktree first-class** — spin up a parallel branch for a new agent in one click.
- **Agent Reminder** — macOS notification the moment an agent finishes.
- **Auto-updates** — Sparkle keeps you on the latest release.

## Install

**Download:** [Prowl.dmg](https://github.com/onevcat/Prowl/releases/latest/download/Prowl.dmg) (notarized)

**Homebrew:**

```bash
brew install --cask onevcat/tap/prowl
```

## Requirements

macOS 26.0+

---

## For Developers

A personal fork of [Supacode](https://github.com/supabitapp/supacode), built on [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) and [libghostty](https://github.com/ghostty-org/ghostty), maintained for daily use. Requires [mise](https://mise.jdx.dev/) for dev tooling.

### Build & run

```bash
make build-ghostty-xcframework   # Build GhosttyKit from Zig source
make build-app                   # Build the macOS app (Debug)
make run-app                     # Build, launch, and stream logs
make install-dev-build           # Build Debug and install to /Applications
make install-release             # Build Release, sign locally, install to /Applications
```

### Develop & test

```bash
make check                 # swift-format + swiftlint
make format                # Format only
make lint                  # Lint only
make test                  # Run app/unit tests
make log-stream            # Stream app logs (subsystem: com.onevcat.prowl)
```

### CLI

```bash
make build-cli             # Build `prowl` CLI via SwiftPM
make test-cli-smoke        # Quick CLI smoke checks
make test-cli-integration  # End-to-end CLI socket integration tests
```

### Ghostty sync

```bash
make ensure-ghostty        # Fast SHA check (auto-run by build-app/test)
make sync-ghostty          # Force rebuild + clear DerivedData
```

### Release

Day-to-day releases are driven by the `release` [Claude Code](https://claude.com/product/claude-code) skill defined in [`.claude/skills/release/SKILL.md`](.claude/skills/release/SKILL.md). It wraps two scripts you can also run directly:

```bash
./doc-onevcat/scripts/release-notes.sh <VERSION>   # Generate user-facing notes → build/release-notes.md
./doc-onevcat/scripts/release.sh <VERSION>         # Bump, build, sign, notarize, DMG, appcast, GitHub Release, Prowl-Site update
```

The skill walks the flow interactively: verify branch & tree state, confirm the version, review the generated notes, then run `release.sh`. All fork releases are notarized.
