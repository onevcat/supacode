# CLI Contract: `prowl read`

Status: draft truth source for `#69`.

This file defines the **JSON output contract** for:

- `prowl read --json`
- `prowl read --last <n> --json`

## Contract goals

- JSON output must carry the actual captured text, not just metadata.
- The payload must say whether the text came from the visible screen, scrollback, or a best-effort mix of both.
- `--last N` should have a stable machine-readable shape even if the first implementation is best-effort.

## Supported targeting

- `--worktree <id|name|path>`
- `--tab <id>`
- `--pane <id>`
- no selector, meaning current focused pane

## Success payload

```json
{
  "ok": true,
  "command": "read",
  "schema_version": "prowl.cli.read.v1",
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
        "title": "build",
        "cwd": "/Users/onevcat/Projects/Prowl",
        "focused": true
      }
    },
    "mode": "last",
    "last": 100,
    "source": "scrollback",
    "truncated": false,
    "line_count": 87,
    "text": "Compile Swift module ProwlCore\n..."
  }
}
```

## Required top-level fields

- `ok`: boolean, must be `true` on success.
- `command`: string, must be `"read"`.
- `schema_version`: string, currently `"prowl.cli.read.v1"`.
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

## `data` capture fields

- `mode`: `"snapshot"` | `"last"`
  - `"snapshot"` for plain `prowl read`
  - `"last"` for `prowl read --last N`
- `last`: integer or `null`
  - required as an integer when `mode == "last"`
  - must be `null` when `mode == "snapshot"`
- `source`: `"screen"` | `"scrollback"` | `"mixed"`
  - `"screen"`: visible screen snapshot only
  - `"scrollback"`: satisfied from scrollback/history
  - `"mixed"`: combined view when the runtime had to stitch sources together
- `truncated`: boolean
  - `true` when the runtime could not return the full requested text volume
- `line_count`: integer
  - number of newline-delimited lines present in `text`
- `text`: string
  - UTF-8 text payload
  - may be empty if the target pane currently has no readable text

## Output invariants

- `text` is always present on success, even when empty.
- `line_count` must describe the returned text, not the requested amount.
- `mode == "last"` does not guarantee exact history completeness; that uncertainty is represented by `source` and `truncated`, not by changing the response shape.

## Error payload

```json
{
  "ok": false,
  "command": "read",
  "schema_version": "prowl.cli.read.v1",
  "error": {
    "code": "TARGET_NOT_FOUND",
    "message": "No pane matched '6E1A2A10-D99F-4E3F-920C-D93AA3C05764'"
  }
}
```

## Error codes for v1

- `APP_NOT_RUNNING`
- `INVALID_ARGUMENT`
- `TARGET_NOT_FOUND`
- `TARGET_NOT_UNIQUE`
- `READ_FAILED`

## Notes

- The parent issue explicitly requires `--last N` to cover recent history beyond the visible screen when possible, so `source` is a first-class field in the contract.
- The contract does not include ANSI styling or structured screen cells in v1; JSON is text-first.
- Future richer output can add optional fields, but `text` must remain the primary machine-facing content.

## Example: visible snapshot

```json
{
  "ok": true,
  "command": "read",
  "schema_version": "prowl.cli.read.v1",
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
        "title": "zsh",
        "cwd": "/Users/onevcat/Projects/Prowl",
        "focused": true
      }
    },
    "mode": "snapshot",
    "last": null,
    "source": "screen",
    "truncated": false,
    "line_count": 12,
    "text": "onevcat@mini Prowl % swift test\n..."
  }
}
```
