# CLI Contract: `prowl list`

Status: draft truth source for `#65`.

This file defines the **JSON output contract** for:

- `prowl list --json`

Non-JSON `prowl list` remains human-readable text and is intentionally outside this file.

## Contract goals

- JSON output is **pane-oriented**: one array item per actionable pane.
- The payload must expose enough information for follow-up commands such as `focus`, `send`, `key`, and `read`.
- IDs must be stable within the current running instance and must be returned as strings.

## Success payload

```json
{
  "ok": true,
  "command": "list",
  "schema_version": "prowl.cli.list.v1",
  "data": {
    "count": 2,
    "items": [
      {
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
        },
        "task": {
          "status": "running"
        }
      },
      {
        "worktree": {
          "id": "Notes:/Users/onevcat/Projects/Notes",
          "name": "Notes",
          "path": "/Users/onevcat/Projects/Notes",
          "root_path": "/Users/onevcat/Projects/Notes",
          "kind": "plain"
        },
        "tab": {
          "id": "A2B07BBA-9DD0-4C77-9D76-2B3E0AF12096",
          "title": "Notes",
          "selected": false
        },
        "pane": {
          "id": "EF65FF31-1B72-40B2-80DA-3AA87B7B6858",
          "title": "Notes",
          "cwd": "/Users/onevcat/Projects/Notes",
          "focused": false
        },
        "task": {
          "status": "idle"
        }
      }
    ]
  }
}
```

## Required top-level fields

- `ok`: boolean, must be `true` on success.
- `command`: string, must be `"list"`.
- `schema_version`: string, currently `"prowl.cli.list.v1"`.
- `data`: object.

## `data` fields

- `count`: integer, must equal `items.length`.
- `items`: array of pane rows.

## Pane row shape

Every item in `data.items` represents exactly one actionable pane.

### `worktree`

- `id`: string
- `name`: string
- `path`: string, absolute path to the worktree or plain folder shown in the UI
- `root_path`: string, absolute repository root or plain-folder root
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

### `task`

- `status`: `"idle"` | `"running"` | `null`
  - `null` is allowed when runtime state is unavailable for that pane/worktree.

## Output invariants

- `tab.selected == true` means the row's tab is the currently selected tab of that worktree.
- `pane.focused == true` means the row is the current focused pane within its selected tab.
- At most one row in the whole payload should have `pane.focused == true`.
- A worktree with split panes returns multiple rows that share the same `worktree` and `tab` objects but differ in `pane`.
- The array order should be stable for a single call. Preferred order: worktree order, then tab order, then pane order.

## Error payload

```json
{
  "ok": false,
  "command": "list",
  "schema_version": "prowl.cli.list.v1",
  "error": {
    "code": "APP_NOT_RUNNING",
    "message": "Prowl is not running"
  }
}
```

## Error codes for v1

- `APP_NOT_RUNNING`
- `LIST_FAILED`

## Notes

- `list --json` is the discovery primitive for all later target-based commands.
- `cwd` should be the best available runtime working directory for the pane; when unavailable it must be `null`, not an invented fallback string.
- `task.status` is intentionally coarse in v1 because the parent issue only requires “running status (if available)”.

## Example: split tab

```json
{
  "ok": true,
  "command": "list",
  "schema_version": "prowl.cli.list.v1",
  "data": {
    "count": 2,
    "items": [
      {
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
        },
        "task": {
          "status": "running"
        }
      },
      {
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
          "id": "1344AEF5-3BA6-4B75-A07E-1F36C63A34B0",
          "title": "tests",
          "cwd": "/Users/onevcat/Projects/Prowl",
          "focused": false
        },
        "task": {
          "status": "idle"
        }
      }
    ]
  }
}
```
