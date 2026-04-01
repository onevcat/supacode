# CLI Contract: `prowl open`

Status: draft truth source for `#64`.

This file defines the **JSON output contract** for the path-opening entry points:

- `prowl`
- `prowl <cwd>`
- `prowl open <cwd>`
- any of the above with `--json`

The goal is to give later implementation tasks a stable machine-facing contract.

## Contract goals

- Bare `prowl <cwd>` and explicit `prowl open <cwd>` must share the same JSON shape.
- Success output must tell an agent **what Prowl actually focused or opened**.
- Path fields must be normalized to **absolute paths** after CLI parsing.
- Success output must be stable enough for scripts; human-oriented prose belongs to non-JSON mode.

## Success payload

```json
{
  "ok": true,
  "command": "open",
  "schema_version": "prowl.cli.open.v1",
  "data": {
    "invocation": "implicit-open",
    "requested_path": "/Users/onevcat/Projects/Prowl/supacode",
    "resolved_path": "/Users/onevcat/Projects/Prowl/supacode",
    "resolution": "inside-root",
    "app_launched": false,
    "brought_to_front": true,
    "created_tab": true,
    "target": {
      "worktree": {
        "id": "Prowl:/Users/onevcat/Projects/Prowl",
        "name": "Prowl",
        "path": "/Users/onevcat/Projects/Prowl",
        "root_path": "/Users/onevcat/Projects/Prowl",
        "kind": "git"
      },
      "tab": {
        "id": "0E2A7C03-9C01-4BC1-9327-6C1C7B629A52",
        "title": "supacode",
        "cwd": "/Users/onevcat/Projects/Prowl/supacode"
      },
      "pane": {
        "id": "0FB4DDB4-A797-4315-A00E-8AAFB32BFC95",
        "title": "supacode",
        "cwd": "/Users/onevcat/Projects/Prowl/supacode"
      }
    }
  }
}
```

## Required top-level fields

- `ok`: boolean, must be `true` on success.
- `command`: string, must be `"open"` even when the user invoked bare `prowl <cwd>`.
- `schema_version`: string, currently `"prowl.cli.open.v1"`.
- `data`: object.

## `data` fields

- `invocation`: string.
  - `"bare"` for `prowl`
  - `"implicit-open"` for `prowl <cwd>`
  - `"open-subcommand"` for `prowl open <cwd>`
- `requested_path`: string or `null`.
  - `null` only for bare `prowl` with no explicit path.
  - otherwise the absolute path after resolving `.` / `..` / `~` / `file://`.
- `resolved_path`: string or `null`.
  - `null` only when `requested_path` is `null`.
  - must be the path Prowl actually targeted after normalization.
- `resolution`: string enum.
  - `"no-argument"`: bare `prowl`
  - `"exact-root"`: requested path matched an already-open root exactly
  - `"inside-root"`: requested path was inside an already-open root, so Prowl focused that root and opened a tab at the exact subpath
  - `"new-root"`: requested path was not yet managed and Prowl opened it as a new root
- `app_launched`: boolean.
  - `true` only when the command had to start Prowl.
- `brought_to_front`: boolean.
  - must be `true` on success.
- `created_tab`: boolean.
  - `true` when the operation created a new tab as part of satisfying the request.
  - `false` when Prowl only focused an existing target.
- `target`: object describing the final focused target.

## `target` shape

### `target.worktree`

- `id`: string
- `name`: string
- `path`: string, absolute worktree/plain-folder path
- `root_path`: string, absolute repository root or plain-folder root
- `kind`: `"git"` | `"plain"`

### `target.tab`

- `id`: string, UUID text form
- `title`: string
- `cwd`: string or `null`

### `target.pane`

- `id`: string, UUID text form
- `title`: string
- `cwd`: string or `null`

## Error payload

```json
{
  "ok": false,
  "command": "open",
  "schema_version": "prowl.cli.open.v1",
  "error": {
    "code": "PATH_NOT_FOUND",
    "message": "No directory exists at '/Users/onevcat/Projects/Missing'",
    "details": {
      "requested_path": "/Users/onevcat/Projects/Missing"
    }
  }
}
```

## Required error fields

- `ok`: boolean, must be `false`.
- `command`: string, must be `"open"`.
- `schema_version`: string, must be `"prowl.cli.open.v1"`.
- `error.code`: stable machine-readable string.
- `error.message`: human-readable string.
- `error.details`: optional object with structured context.

## Error codes for v1

- `INVALID_ARGUMENT`
- `PATH_NOT_FOUND`
- `PATH_NOT_DIRECTORY`
- `PATH_NOT_ALLOWED`
- `LAUNCH_FAILED`
- `OPEN_FAILED`

## Notes

- Success JSON should report the **resolved target**, not only the input path.
- `target.tab.cwd` and `target.pane.cwd` should be the exact directory the user lands in when available.
- `created_tab` may be `false` for `exact-root` and `true` for `inside-root`; `new-root` may do either depending on implementation, so callers must trust the boolean instead of inferring it.
- `prowl` without arguments still returns `command: "open"`; it is the app-entry form of the same capability.

## Example: exact-root focus

```json
{
  "ok": true,
  "command": "open",
  "schema_version": "prowl.cli.open.v1",
  "data": {
    "invocation": "open-subcommand",
    "requested_path": "/Users/onevcat/Projects/Prowl",
    "resolved_path": "/Users/onevcat/Projects/Prowl",
    "resolution": "exact-root",
    "app_launched": false,
    "brought_to_front": true,
    "created_tab": false,
    "target": {
      "worktree": {
        "id": "Prowl:/Users/onevcat/Projects/Prowl",
        "name": "Prowl",
        "path": "/Users/onevcat/Projects/Prowl",
        "root_path": "/Users/onevcat/Projects/Prowl",
        "kind": "git"
      },
      "tab": {
        "id": "95A6DF8D-4E7E-4A67-895B-0EAF7DB6D7A8",
        "title": "Prowl 1",
        "cwd": "/Users/onevcat/Projects/Prowl"
      },
      "pane": {
        "id": "7C38206E-1C9D-4740-A6B0-675C3BC93B47",
        "title": "Prowl",
        "cwd": "/Users/onevcat/Projects/Prowl"
      }
    }
  }
}
```
