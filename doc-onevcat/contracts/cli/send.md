# CLI Contract: `prowl send`

Status: draft truth source for `#67`.

This file defines the **JSON output contract** for:

- `prowl send ... --json`

## Contract goals

- `send` must report **where** text was delivered and **how** it was delivered.
- JSON output must never echo the full text payload back by default; scripts often send secrets, prompts, or long commands.
- The success payload must describe whether Enter was sent and whether the command had to create a tab first.

## Supported targeting

- `--worktree <id|name|path>`
- `--tab <id>`
- `--pane <id>`
- no selector, meaning current focused pane

## Supported input forms

- positional text argument
- stdin text
- `--no-enter`

### Input source semantics

`data.input.source` is **inferred from where the accepted payload came from**. It is not a separate `--source` flag.

- `"argv"`
  - means the payload came from the positional text argument of `prowl send`
  - typical trigger: `prowl send "echo hello"`
  - planned use: short, explicit, human-authored inline sends
- `"stdin"`
  - means the payload came from process stdin, usually via a pipe or redirection
  - typical trigger: `printf 'echo hello\n' | prowl send`
  - planned use: multiline text, generated text, file/pipe input, or payloads you do not want to expose inline in shell history

## Success payload

```json
{
  "ok": true,
  "command": "send",
  "schema_version": "prowl.cli.send.v1",
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
    "input": {
      "source": "argv",
      "characters": 10,
      "bytes": 10,
      "trailing_enter_sent": true
    },
    "created_tab": false
  }
}
```

## Required top-level fields

- `ok`: boolean, must be `true` on success.
- `command`: string, must be `"send"`.
- `schema_version`: string, currently `"prowl.cli.send.v1"`.
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
- `selected`: boolean, should be `true` when the target tab is also the selected tab

### `pane`

- `id`: string, UUID text form
- `title`: string
- `cwd`: string or `null`
- `focused`: boolean

## `data.input` fields

- `source`: `"argv"` | `"stdin"`
  - `"argv"`: accepted payload came from the positional command argument
  - `"stdin"`: accepted payload came from stdin
  - the reported value must match the actual accepted payload source
- `characters`: integer, count of Unicode scalar content accepted for delivery
- `bytes`: integer, UTF-8 byte count of content accepted for delivery
- `trailing_enter_sent`: boolean
  - `true` for default behavior
  - `false` when `--no-enter` is used

## `data.created_tab`

- boolean
- `true` only when targeting a worktree that had no current tab and Prowl had to create one before sending.

## Output invariants

- The payload must describe the **resolved pane** that received the text.
- The payload must **not** include the original text body.
- If stdin is empty, the command should fail instead of pretending that an empty payload was delivered.
- `characters` and `bytes` refer only to the text payload, not the synthetic Enter keypress.

## Error payload

```json
{
  "ok": false,
  "command": "send",
  "schema_version": "prowl.cli.send.v1",
  "error": {
    "code": "EMPTY_INPUT",
    "message": "No text payload was provided"
  }
}
```

## Error codes for v1

- `APP_NOT_RUNNING`
- `INVALID_ARGUMENT`
- `TARGET_NOT_FOUND`
- `TARGET_NOT_UNIQUE`
- `EMPTY_INPUT`
- `SEND_FAILED`

## Notes

- `send` is text delivery, not general key simulation. Control inputs such as `ctrl-c` belong to `key`.
- Returning byte and character counts gives scripts enough confirmation without leaking payload contents into logs.
- A future implementation may add optional debug echo flags, but v1 default JSON must stay redaction-friendly.

## Example: stdin + `--no-enter`

```json
{
  "ok": true,
  "command": "send",
  "schema_version": "prowl.cli.send.v1",
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
    "input": {
      "source": "stdin",
      "characters": 24,
      "bytes": 24,
      "trailing_enter_sent": false
    },
    "created_tab": false
  }
}
```
