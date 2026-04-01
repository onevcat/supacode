# CLI Contract: `prowl key`

Status: draft truth source for `#68`.

This file defines the **input/output contract** for:

- `prowl key ... --json`

## What changed in this revision

Compared with the initial draft, this version makes `key` safer and more script-friendly:

- define a strict input grammar with aliases (`return` -> `enter`, `escape` -> `esc`, `pgup` -> `pageup`, ...)
- add `--repeat <n>` as first-class input instead of forcing shell loops
- split `requested` vs `normalized` in output so callers can debug token normalization
- add `delivery` counters for machine verification (`attempted` / `delivered`)
- require `key` to target an existing pane context (no implicit tab creation)

## Contract goals

- `key` should be deterministic for agent loops and TUI automation.
- output must clearly answer:
  - what was requested
  - what token was actually accepted
  - where it was delivered
  - how many key events were delivered
- keep key semantics separate from `send` (text input) and avoid hidden side effects.

## Recommended usage

- Prefer `--pane <id>` for deterministic scripting.
- Use `--tab` / `--worktree` for human-friendly calls when exact pane ID is not needed.
- Typical loop:
  1) `prowl list --json`
  2) resolve target pane
  3) `prowl key --pane <pane-id> <token> [--repeat n]`
  4) `prowl read --pane <pane-id> --last <n> --json`

## Supported targeting

- `--worktree <id|name|path>`
- `--tab <id>`
- `--pane <id>`
- no selector, meaning current focused pane

## Input contract (v1)

### Positional token

```bash
prowl key [target selectors] <token> [--repeat <n>] [--json]
```

Rules:

- exactly one positional `<token>` is required
- parsing is case-insensitive
- surrounding spaces are ignored
- canonical token form is lowercase kebab-case

### Canonical tokens

- `enter`
- `esc`
- `tab`
- `backspace`
- `up`
- `down`
- `left`
- `right`
- `pageup`
- `pagedown`
- `home`
- `end`
- `ctrl-c`
- `ctrl-d`
- `ctrl-l`

### Accepted aliases (normalized to canonical)

- `return` -> `enter`
- `escape` -> `esc`
- `arrow-up` -> `up`
- `arrow-down` -> `down`
- `arrow-left` -> `left`
- `arrow-right` -> `right`
- `pgup` -> `pageup`
- `pgdn` -> `pagedown`
- `ctrl+c` -> `ctrl-c`
- `ctrl+d` -> `ctrl-d`
- `ctrl+l` -> `ctrl-l`

### `--repeat`

- optional, integer, default `1`
- valid range in v1: `1...100`
- repeat means “deliver the same normalized key token N times”

## Success payload

```json
{
  "ok": true,
  "command": "key",
  "schema_version": "prowl.cli.key.v1",
  "data": {
    "requested": {
      "token": "Ctrl+C",
      "repeat": 3
    },
    "key": {
      "normalized": "ctrl-c",
      "category": "control"
    },
    "delivery": {
      "attempted": 3,
      "delivered": 3,
      "mode": "keyDownUp"
    },
    "target": {
      "worktree": {
        "id": "Prowl:/Users/onevcat/Projects/Prowl",
        "name": "Prowl",
        "path": "/Users/onevcat/Projects/Prowl",
        "root_path": "/Users/onevcat/Projects/Prowl",
        "kind": "git"
      },
      "tab": {
        "id": "2FC00CF0-3974-4E1B-BEF8-7A08A8E3B7C0",
        "title": "Prowl 1",
        "selected": true
      },
      "pane": {
        "id": "6E1A2A10-D99F-4E3F-920C-D93AA3C05764",
        "title": "Claude",
        "cwd": "/Users/onevcat/Projects/Prowl",
        "focused": true
      }
    }
  }
}
```

## Required top-level fields

- `ok`: boolean, must be `true` on success.
- `command`: string, must be `"key"`.
- `schema_version`: string, currently `"prowl.cli.key.v1"`.
- `data`: object.

## `data` fields

### `requested`

- `token`: string
  - raw user token after trimming
- `repeat`: integer
  - parsed repeat count

### `key`

- `normalized`: string
  - canonical token used by runtime
  - must be one of the canonical tokens listed above
- `category`: `"navigation"` | `"editing"` | `"control"`

### `delivery`

- `attempted`: integer
  - equals `requested.repeat`
- `delivered`: integer
  - number of successful key deliveries
- `mode`: string
  - `"keyDownUp"` for v1

### `target`

Same shape used by other CLI contracts:

#### `worktree`

- `id`: string
- `name`: string
- `path`: string, absolute path
- `root_path`: string, absolute path
- `kind`: `"git"` | `"plain"`

#### `tab`

- `id`: string, UUID text form
- `title`: string
- `selected`: boolean

#### `pane`

- `id`: string, UUID text form
- `title`: string
- `cwd`: string or `null`
- `focused`: boolean

## Output invariants

- payload must resolve to the final pane that received the key event(s)
- `requested.token` may differ from `key.normalized` when an alias was used
- `delivery.attempted == requested.repeat`
- success requires `delivery.delivered == delivery.attempted`
- unlike `send`, `key` must not create a new tab implicitly; no active pane means error
- JSON should not expose low-level keycodes/modifier bitmasks in v1

## Error payload

```json
{
  "ok": false,
  "command": "key",
  "schema_version": "prowl.cli.key.v1",
  "error": {
    "code": "UNSUPPORTED_KEY",
    "message": "The key token 'ctrl-z' is not supported in v1",
    "details": {
      "token": "ctrl-z"
    }
  }
}
```

## Error codes for v1

- `APP_NOT_RUNNING`
- `INVALID_ARGUMENT`
- `INVALID_REPEAT`
- `TARGET_NOT_FOUND`
- `TARGET_NOT_UNIQUE`
- `NO_ACTIVE_PANE`
- `UNSUPPORTED_KEY`
- `KEY_DELIVERY_FAILED`

## Notes

- `key` is control/navigation input; normal text remains `send`.
- aliases are accepted for UX, but output always returns canonical `normalized` token.
- this contract intentionally allows future token aliases without breaking script logic.

## Example: alias + repeat

```json
{
  "ok": true,
  "command": "key",
  "schema_version": "prowl.cli.key.v1",
  "data": {
    "requested": {
      "token": "return",
      "repeat": 2
    },
    "key": {
      "normalized": "enter",
      "category": "editing"
    },
    "delivery": {
      "attempted": 2,
      "delivered": 2,
      "mode": "keyDownUp"
    },
    "target": {
      "worktree": {
        "id": "Prowl:/Users/onevcat/Projects/Prowl",
        "name": "Prowl",
        "path": "/Users/onevcat/Projects/Prowl",
        "root_path": "/Users/onevcat/Projects/Prowl",
        "kind": "git"
      },
      "tab": {
        "id": "2FC00CF0-3974-4E1B-BEF8-7A08A8E3B7C0",
        "title": "Prowl 1",
        "selected": true
      },
      "pane": {
        "id": "6E1A2A10-D99F-4E3F-920C-D93AA3C05764",
        "title": "zsh",
        "cwd": "/Users/onevcat/Projects/Prowl",
        "focused": true
      }
    }
  }
}
```