# CLI Contract: `prowl focus`

Status: draft truth source for `#66`.

This file defines the **JSON output contract** for:

- `prowl focus ... --json`

## Contract goals

- JSON success output must resolve the caller's selector into the **actual focused pane context**.
- `focus` must return enough information for a script to immediately chain into `send`, `key`, or `read` without another `list` call.
- Ambiguous or missing targets must fail with explicit machine-readable errors.

## Supported selectors

- `--worktree <id|name|path>`
- `--tab <id>`
- `--pane <id>`
- no selector, meaning “focus current target”

## Success payload

```json
{
  "ok": true,
  "command": "focus",
  "schema_version": "prowl.cli.focus.v1",
  "data": {
    "requested": {
      "selector": "worktree",
      "value": "Prowl"
    },
    "resolved_via": "worktree",
    "brought_to_front": true,
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

## Required top-level fields

- `ok`: boolean, must be `true` on success.
- `command`: string, must be `"focus"`.
- `schema_version`: string, currently `"prowl.cli.focus.v1"`.
- `data`: object.

## `data` fields

### `requested`

- `selector`: `"worktree"` | `"tab"` | `"pane"` | `"current"`
- `value`: string or `null`
  - `null` only when `selector == "current"`.

### `resolved_via`

- `"worktree"` | `"tab"` | `"pane"`
- Represents the precision of the final resolution step.
- Examples:
  - `focus --worktree ...` usually returns `"worktree"`
  - `focus --tab ...` returns `"tab"`
  - `focus --pane ...` returns `"pane"`
  - `focus` with no selector returns whichever concrete target was already active

### `brought_to_front`

- boolean
- Must be `true` on success.

### `target`

The final focused context after the command completed.

#### `target.worktree`

- `id`: string
- `name`: string
- `path`: string, absolute path
- `root_path`: string, absolute path
- `kind`: `"git"` | `"plain"`

#### `target.tab`

- `id`: string, UUID text form
- `title`: string
- `selected`: boolean, must be `true` on success

#### `target.pane`

- `id`: string, UUID text form
- `title`: string
- `cwd`: string or `null`
- `focused`: boolean, must be `true` on success

## Output invariants

- A successful `focus` call always returns the final pane that became active, even when the caller selected only a worktree or tab.
- `target.tab.selected` and `target.pane.focused` must both be `true` on success.
- When the selector is less precise than pane, the runtime may choose the already-focused pane within the resolved tab/worktree.

## Error payload

```json
{
  "ok": false,
  "command": "focus",
  "schema_version": "prowl.cli.focus.v1",
  "error": {
    "code": "TARGET_NOT_UNIQUE",
    "message": "Worktree selector 'Prowl' matched more than one target",
    "details": {
      "selector": "worktree",
      "value": "Prowl"
    }
  }
}
```

## Error codes for v1

- `APP_NOT_RUNNING`
- `INVALID_ARGUMENT`
- `TARGET_NOT_FOUND`
- `TARGET_NOT_UNIQUE`
- `FOCUS_FAILED`

## Notes

- The contract intentionally returns the fully resolved pane context so callers can avoid an immediate follow-up discovery pass.
- `focus --worktree` and `focus --tab` do not need to invent new IDs; they must report the IDs of the tab and pane that actually became active.
- A future richer selection model can extend `details`, but the v1 top-level shape should stay stable.

## Example: `--pane`

```json
{
  "ok": true,
  "command": "focus",
  "schema_version": "prowl.cli.focus.v1",
  "data": {
    "requested": {
      "selector": "pane",
      "value": "6E1A2A10-D99F-4E3F-920C-D93AA3C05764"
    },
    "resolved_via": "pane",
    "brought_to_front": true,
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
        "title": "build",
        "cwd": "/Users/onevcat/Projects/Prowl",
        "focused": true
      }
    }
  }
}
```
