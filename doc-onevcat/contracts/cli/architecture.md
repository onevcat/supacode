# CLI Architecture & App Interaction Plan (Phase 1)

Status: implementation plan for `#70` after contract alignment.

This plan defines where CLI logic lives, how requests are transported to a running app, and how command execution is routed inside Prowl.

---

## 1) Goals

- Make `prowl` a stable machine interface for a running Prowl instance.
- Keep parsing and validation outside app runtime logic.
- Reuse existing repository/terminal capabilities instead of rebuilding terminal core.
- Align runtime behavior with contract docs under `doc-onevcat/contracts/cli/`.

---

## 2) Architectural decision (v1)

## Decision A: first-class CLI binary

`prowl` MUST be implemented as a first-class Swift executable (ArgumentParser-based), not shell-script business logic.

- Existing `bin/prowl` shell implementation is discarded.
- Parsing truth and input validation must live in Swift CLI module.

Why:

- strict typed request model
- easier testability (unit tests for parser)
- deterministic behavior across commands
- lower long-term drift vs app contracts

## Decision B: explicit app command service boundary

CLI communicates with app through a dedicated command service boundary:

- CLI side: build normalized command request
- App side: resolve target + execute + return normalized response

App should not re-interpret argv-level ambiguity.

## Decision C: command execution is app-owned

Phase-1 commands are **remote-control actions on running app state**.

- Open/path, list, focus, send, key, read all execute in app process context.
- `open` must be able to launch app when it is not running.
- CLI is transport + contract adapter, not a parallel runtime.

---

## 3) Proposed module layout

## 3.1 CLI side

`ProwlCLI` target:

- `CommandParser`
  - ArgumentParser commands and options
  - validation and normalization
- `InputModel`
  - typed `OpenInput/ListInput/...`
- `TransportClient`
  - send request to running app
  - receive structured response
- `OutputRenderer`
  - `--json`: raw contract payload
  - text mode: readable summary

## 3.2 App side

`CLICommandService` (new boundary in app):

- `CommandRouter`
  - map command envelope -> handler
- Handlers
  - `OpenCommandHandler`
  - `ListCommandHandler`
  - `FocusCommandHandler`
  - `SendCommandHandler`
  - `KeyCommandHandler`
  - `ReadCommandHandler`
- Shared services
  - `TargetResolver`
  - `TerminalCommandBridge`
  - `RepositorySelectionBridge`

Handlers should return response objects already matching v1 contracts.

---

## 4) Transport plan

v1 target: **single local IPC channel** (implementation choice can be refined), but API contract is fixed:

```swift
request(CommandEnvelope) -> CommandResponse
```

Transport requirements:

- local machine only
- talk to existing running app instance
- clear app-not-running error mapping
- request timeout + cancellation mapping

If transport fails:

- return command-specific failure with stable `error.code`
- avoid leaking transport internals in machine contract

---

## 5) App interaction flow (command lifecycle)

1. CLI parses argv + stdin -> normalized typed input.
2. CLI builds command envelope (`command`, `outputMode`, `requestId` optional).
3. CLI sends envelope to app command service.
4. App command router resolves target context and executes action.
5. For open-entry commands, if app is not running, app launch is part of command execution.
6. App returns structured success/error response.
7. CLI renders JSON or text.

This ensures one authoritative runtime path for both GUI-triggered and CLI-triggered actions.

---

## 6) Target resolution ownership

Resolution belongs to app runtime (state-aware), with CLI only enforcing selector syntax:

- CLI checks selector validity and exclusivity.
- App maps selector to concrete `worktree/tab/pane` in current state.
- App returns resolved target in output (per existing contracts).

---

## 7) Mapping to existing contracts

- Input normalization rules: `input.md`
- Output contracts:
  - `open.md`
  - `list.md`
  - `focus.md`
  - `send.md`
  - `key.md`
  - `read.md`
- JSON schema validation source:
  - `schema.md`

Implementation MUST be validated against `schema.md` for `--json` mode.

---

## 8) Plan by milestones

## M0 — contract lock

- Land `input.md` and this architecture plan.
- Freeze selector, stdin/argv, key repeat, read-last semantics.

## M1 — parser/runtime split

- Introduce Swift `prowl` executable target.
- Discard shell implementation and keep command parsing in Swift only.

## M2 — command service scaffold

- Add app-side command router and handler protocols.
- Implement no-op or open-only path to verify transport.

## M3 — implement phase-1 handlers

- `open` behavior aligned with #64
- `list/focus/send/key/read` wired to existing terminal/repository features
- full error-code mapping per contracts

## M4 — test and harden

- parser unit tests (argv matrix)
- contract tests (`--json` payload schema validation)
- integration tests for `list->focus->send/key->read` loops

---

## 9) Testing strategy

- Parser golden tests:
  - valid/invalid token combinations
  - selector exclusivity
  - stdin/argv source rules for `send`
  - `--last` and `--repeat` constraints
- Contract tests:
  - validate JSON against `schema.md` refs per subcommand
- Runtime integration tests:
  - open exact-root / inside-root / new-root
  - key alias normalization and repeat delivery counters
  - read source/mode/last semantics

---

## 10) Why this supersedes ad-hoc approach

This plan intentionally prevents a repeat of mixed concerns where:

- parser logic lives in shell
- app behavior evolves independently
- CI churn appears before contract decisions are final

By locking input + architecture first, we can implement all commands consistently and avoid contract drift.
