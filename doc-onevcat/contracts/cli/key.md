# CLI Contract: `prowl key`

Status: draft truth source for `#68`.

This file defines the **JSON output contract** for:

- `prowl key ... --json`

## Contract goals

- `key` must report which normalized key token was accepted and where it was delivered.
- JSON output should be simple enough for agent loops: send key, then maybe read output.
- The command should expose a canonical key token so scripts do not need to reverse-engineer internal AppKit details.

## Supported targeting

- `--worktree <id|name|path>`
- `--tab <id>`
- `--pane <id>`
- no selector, meaning current focused pane

## v1 canonical key tokens

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

## Success payload

```json
{
  "ok": true,
  "command": "key",
  "schema_version": "prowl.cli.key.v1",
  "data": {
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
    },
    "key": {
      "token": "ctrl-c",
      "normalized": "ctrl-c"
    }
  }
}
```

## Required top-level fields

- `ok`: boolean, must be `true` on success.
- `command`: string, must be `"key"`.
- `schema_version`: string, currently `"prowl.cli.key.v1"`.
- `data`: object.

## `data.target` shape

### `worktree`

- `id`: string
- `name`: string
- `path`: string, absolute path
- `root_path`: string, absolute path
- `kind`: `"git"` | `"plain"`

### `tab`

- `id`: string, UUID text form
- `title`: string
- `selected`: boolean

### `pane`

- `id`: string, UUID text form
- `title`: string
- `cwd`: string or `null`
- `focused`: boolean

## `data.key` fields

- `token`: string
  - the token exactly accepted from the CLI after trimming and case normalization
- `normalized`: string
  - canonical token emitted by the runtime
  - in v1, this should equal one of the tokens listed above

## Output invariants

- The payload must resolve to the final pane that received the key event.
- `normalized` exists so future aliases can still collapse to a stable form.
- The JSON response does not need to expose low-level key codes or modifier masks.

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
- `TARGET_NOT_FOUND`
- `TARGET_NOT_UNIQUE`
- `UNSUPPORTED_KEY`
- `KEY_DELIVERY_FAILED`

## Notes

- v1 exposes command-level tokens, not a general keyboard encoding system.
- The issue text calls out `pageup`, `pagedown`, `home`, and `end`; even if the first implementation is internally approximate, the outward token names should remain stable.
- `key` is intentionally separate from `send`; it should never pretend that control keys are text input.

## Example: simple navigation key

```json
{
  "ok": true,
  "command": "key",
  "schema_version": "prowl.cli.key.v1",
  "data": {
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
        "title": "fzf",
        "cwd": "/Users/onevcat/Projects/Prowl",
        "focused": true
      }
    },
    "key": {
      "token": "down",
      "normalized": "down"
    }
  }
}
```
