# CLI Input Contract: `prowl` (v1)

Status: draft truth source for `#70` implementation.

This file defines **input-side** rules for the phase-1 CLI commands:

- `open`
- `list`
- `focus`
- `send`
- `key`
- `read`

It complements output contracts under `doc-onevcat/contracts/cli/{open,list,focus,send,key,read}.md`.

---

## 1) Design goals

- One stable command grammar for both humans and agents.
- No hidden priority chains that make scripts nondeterministic.
- Parse once in CLI layer; app layer should receive already-normalized typed requests.
- Keep command behavior composable: `list -> focus/send/key/read`.

---

## 2) Global command model

### 2.1 Canonical form

```bash
prowl <subcommand> [target-selector] [command-args] [output-options]
```

### 2.2 Supported subcommands (v1)

- `open`
- `list`
- `focus`
- `send`
- `key`
- `read`

Global options (not subcommands):

- `--help`
- `--version`

### 2.3 Bare path entry

These are equivalent to `open` entry:

- `prowl`
- `prowl <path-like-first-arg>`
- `prowl open <path>`

Path-like first arg (v1):

- `/...`
- `./...`
- `../...`
- `~/...`
- `file://...`
- `.`
- `..`

### 2.4 `--` handling

`--` stops option parsing and forces following token parsing as positional arguments.

- `prowl -- ./focus` MUST be treated as path entry (`open`), not subcommand `focus`.
- `prowl open -- --weird-dir` MUST treat `--weird-dir` as path.

---

## 3) Target selector contract (shared)

### 3.1 Selector flags

- `--worktree <id|name|path>`
- `--tab <id>`
- `--pane <id>`

### 3.2 Mutual exclusivity (hard rule)

Exactly **zero or one** selector is allowed.

- `0 selector`: operate on current focused target (where command allows it).
- `1 selector`: resolve with that selector.
- `>1 selector`: error `INVALID_ARGUMENT`.

This is preferred over implicit precedence because it is easier to reason about in scripts.

### 3.3 Resolution rules

- `--pane`: exact pane.
- `--tab`: current focused pane of target tab.
- `--worktree`: selected tab + focused pane in target worktree.
- none: currently focused pane in current context.

If required context does not exist:

- return command-specific not-found / no-active-pane error.

---

## 4) Common output flags

### 4.1 `--json`

All phase-1 commands MUST support `--json`.

- With `--json`, output MUST match corresponding schema in `schema.md`.
- Without `--json`, output is human-readable text.

### 4.2 Exit behavior

- Success: exit code `0`
- Failure: non-zero
- Error payload shape in JSON mode MUST follow command contract (`error.code`, `error.message`, optional `error.details`).

(Exact numeric non-zero codes can be refined later; error `code` string is the machine contract.)

---

## 5) Per-command input rules

## 5.1 `open`

### Grammar

```bash
prowl
prowl <path-like>
prowl open <path>
```

### Rules

- `prowl` without path is valid and means “open app / bring to front”.
- `prowl <path-like>` is first-class, not shorthand hack.
- `prowl open <path>` is explicit equivalent for scripts.
- For all open-entry forms, if app is not running, CLI MUST launch Prowl and complete the open/focus flow.
- Path MUST be normalized by CLI:
  - expand `~`
  - resolve relative path to absolute path
  - resolve `file://`
  - normalize `.` / `..`
- If provided path does not exist or is not a directory: error (`PATH_NOT_FOUND` / `PATH_NOT_DIRECTORY`).

## 5.2 `list`

### Grammar

```bash
prowl list [--json]
```

### Rules

- `list` MUST NOT accept target selectors in v1 (it is global discovery).
- Extra positional args: `INVALID_ARGUMENT`.

## 5.3 `focus`

### Grammar

```bash
prowl focus [--worktree <...> | --tab <...> | --pane <...>] [--json]
```

### Rules

- Selectors are optional; no selector means “focus current target and bring app front”.
- More than one selector is invalid.

## 5.4 `send`

### Grammar

```bash
prowl send [selector] [--no-enter] [--json] [<text>]
# or
printf '...' | prowl send [selector] [--no-enter] [--json]
```

### Rules

- Input source is exactly one of:
  - positional `<text>` (`argv`)
  - stdin (`stdin`)
- Both provided simultaneously: `INVALID_ARGUMENT`.
- Neither provided (or empty stdin): `EMPTY_INPUT`.
- Default sends trailing Enter; `--no-enter` disables it.

## 5.5 `key`

### Grammar

```bash
prowl key [selector] <token> [--repeat <n>] [--json]
```

### Rules

- Exactly one positional `<token>` required.
- Token parsing is case-insensitive; canonical output token is lowercase kebab-case.
- Alias normalization follows `key.md`.
- `--repeat` default is `1`, range `1...100`.
- `--repeat` out of range: `INVALID_REPEAT`.

## 5.6 `read`

### Grammar

```bash
prowl read [selector] [--json]
prowl read [selector] --last <n> [--json]
```

### Rules

- `--last` optional; if omitted, mode is `snapshot`.
- `--last <n>` requires integer `n >= 1`; otherwise `INVALID_ARGUMENT`.
- At most one `--last` value.

---

## 6) Reserved command tokens (v1)

These tokens are reserved as first command token:

- `open`
- `list`
- `focus`
- `send`
- `key`
- `read`

If first token matches a reserved command, CLI MUST parse as subcommand unless forced by `--` path form.

`--help` / `--version` are handled as global options, not subcommands.

---

## 7) Normalized request model (input -> typed request)

CLI parser MUST produce one normalized typed request before transport.

Example shape:

```swift
struct CommandEnvelope {
  var output: OutputMode // text | json
  var command: Command
}

enum Command {
  case open(OpenInput)
  case list(ListInput)
  case focus(FocusInput)
  case send(SendInput)
  case key(KeyInput)
  case read(ReadInput)
}
```

This model is the handoff contract to app/transport layer.

---

## 8) Examples (valid / invalid)

Valid:

```bash
prowl .
prowl open ~/Projects/Prowl
prowl focus --pane 6E1A2A10-D99F-4E3F-920C-D93AA3C05764 --json
printf 'git status' | prowl send --worktree Prowl --json
prowl key --pane 6E1A2A10-D99F-4E3F-920C-D93AA3C05764 return --repeat 2 --json
prowl read --tab 2FC00CF0-3974-4E1B-BEF8-7A08A8E3B7C0 --last 200 --json
```

Invalid:

```bash
prowl focus --pane <id> --tab <id>        # multiple selectors
prowl send "echo hi" < /tmp/input.txt     # two input sources
prowl key --repeat 0 enter                 # repeat out of range
prowl list --pane <id>                     # list does not accept selector
```

---

## 9) Non-goals (v1)

- No complex selector query language (`--where ...`).
- No streaming mode for `read`.
- No macro system for `key`.
- No dual parser implementations in v1.
