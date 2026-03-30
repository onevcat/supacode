# Prowl CLI JSON Schema Definitions (v1)

Status: draft truth source for #96.

This file provides machine-validatable JSON Schema definitions for the v1 CLI output contracts described in:

- `open.md`
- `list.md`
- `focus.md`
- `send.md`
- `key.md`
- `read.md`

## Scope

- JSON Schema dialect: **Draft 2020-12**
- Commands covered: `open`, `list`, `focus`, `send`, `key`, `read`
- Each command schema is represented as `oneOf(success, error)`
- Shared objects are centralized in `$defs` and reused by command schemas

## Schema bundle

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://prowl.onev.cat/contracts/cli/v1/schema-bundle.json",
  "title": "Prowl CLI Output Contract Schemas (v1)",
  "description": "Bundle of output JSON schemas for prowl open/list/focus/send/key/read v1",
  "type": "object",
  "additionalProperties": false,
  "$defs": {
    "uuid": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    },
    "absolutePath": {
      "type": "string",
      "minLength": 1,
      "pattern": "^/.*"
    },
    "worktreeKind": {
      "type": "string",
      "enum": ["git", "plain"]
    },
    "worktree": {
      "type": "object",
      "additionalProperties": false,
      "required": ["id", "name", "path", "root_path", "kind"],
      "properties": {
        "id": { "type": "string", "minLength": 1 },
        "name": { "type": "string", "minLength": 1 },
        "path": { "$ref": "#/$defs/absolutePath" },
        "root_path": { "$ref": "#/$defs/absolutePath" },
        "kind": { "$ref": "#/$defs/worktreeKind" }
      }
    },
    "tabBasic": {
      "type": "object",
      "additionalProperties": false,
      "required": ["id", "title"],
      "properties": {
        "id": { "$ref": "#/$defs/uuid" },
        "title": { "type": "string" }
      }
    },
    "paneBasic": {
      "type": "object",
      "additionalProperties": false,
      "required": ["id", "title", "cwd"],
      "properties": {
        "id": { "$ref": "#/$defs/uuid" },
        "title": { "type": "string" },
        "cwd": {
          "type": ["string", "null"],
          "pattern": "^/.*"
        }
      }
    },
    "tabSelected": {
      "allOf": [
        { "$ref": "#/$defs/tabBasic" },
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["selected"],
          "properties": {
            "selected": { "type": "boolean" }
          }
        }
      ]
    },
    "paneFocused": {
      "allOf": [
        { "$ref": "#/$defs/paneBasic" },
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["focused"],
          "properties": {
            "focused": { "type": "boolean" }
          }
        }
      ]
    },
    "openTarget": {
      "type": "object",
      "additionalProperties": false,
      "required": ["worktree", "tab", "pane"],
      "properties": {
        "worktree": { "$ref": "#/$defs/worktree" },
        "tab": { "$ref": "#/$defs/tabBasic" },
        "pane": { "$ref": "#/$defs/paneBasic" }
      }
    },
    "resolvedTarget": {
      "type": "object",
      "additionalProperties": false,
      "required": ["worktree", "tab", "pane"],
      "properties": {
        "worktree": { "$ref": "#/$defs/worktree" },
        "tab": { "$ref": "#/$defs/tabSelected" },
        "pane": { "$ref": "#/$defs/paneFocused" }
      }
    },
    "errorDetails": {
      "type": "object",
      "additionalProperties": true
    },

    "openSuccess": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "data"],
      "properties": {
        "ok": { "const": true },
        "command": { "const": "open" },
        "schema_version": { "const": "prowl.cli.open.v1" },
        "data": {
          "type": "object",
          "additionalProperties": false,
          "required": [
            "invocation",
            "requested_path",
            "resolved_path",
            "resolution",
            "app_launched",
            "brought_to_front",
            "created_tab",
            "target"
          ],
          "properties": {
            "invocation": {
              "type": "string",
              "enum": ["bare", "implicit-open", "open-subcommand"]
            },
            "requested_path": {
              "anyOf": [
                { "$ref": "#/$defs/absolutePath" },
                { "type": "null" }
              ]
            },
            "resolved_path": {
              "anyOf": [
                { "$ref": "#/$defs/absolutePath" },
                { "type": "null" }
              ]
            },
            "resolution": {
              "type": "string",
              "enum": ["no-argument", "exact-root", "inside-root", "new-root"]
            },
            "app_launched": { "type": "boolean" },
            "brought_to_front": { "type": "boolean" },
            "created_tab": { "type": "boolean" },
            "target": { "$ref": "#/$defs/openTarget" }
          },
          "allOf": [
            {
              "if": {
                "properties": { "requested_path": { "type": "null" } },
                "required": ["requested_path"]
              },
              "then": {
                "properties": {
                  "resolved_path": { "type": "null" },
                  "resolution": { "const": "no-argument" }
                }
              }
            },
            {
              "if": {
                "properties": {
                  "invocation": { "const": "bare" }
                },
                "required": ["invocation"]
              },
              "then": {
                "properties": {
                  "requested_path": { "type": "null" }
                }
              }
            }
          ]
        }
      }
    },
    "openError": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "error"],
      "properties": {
        "ok": { "const": false },
        "command": { "const": "open" },
        "schema_version": { "const": "prowl.cli.open.v1" },
        "error": {
          "type": "object",
          "additionalProperties": false,
          "required": ["code", "message"],
          "properties": {
            "code": {
              "type": "string",
              "enum": [
                "INVALID_ARGUMENT",
                "PATH_NOT_FOUND",
                "PATH_NOT_DIRECTORY",
                "PATH_NOT_ALLOWED",
                "LAUNCH_FAILED",
                "OPEN_FAILED"
              ]
            },
            "message": { "type": "string", "minLength": 1 },
            "details": { "$ref": "#/$defs/errorDetails" }
          }
        }
      }
    },
    "openResponse": {
      "oneOf": [
        { "$ref": "#/$defs/openSuccess" },
        { "$ref": "#/$defs/openError" }
      ]
    },

    "listSuccess": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "data"],
      "properties": {
        "ok": { "const": true },
        "command": { "const": "list" },
        "schema_version": { "const": "prowl.cli.list.v1" },
        "data": {
          "type": "object",
          "additionalProperties": false,
          "required": ["count", "items"],
          "properties": {
            "count": { "type": "integer", "minimum": 0 },
            "items": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["worktree", "tab", "pane", "task"],
                "properties": {
                  "worktree": { "$ref": "#/$defs/worktree" },
                  "tab": { "$ref": "#/$defs/tabSelected" },
                  "pane": { "$ref": "#/$defs/paneFocused" },
                  "task": {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["status"],
                    "properties": {
                      "status": {
                        "type": ["string", "null"],
                        "enum": ["idle", "running", null]
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "listError": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "error"],
      "properties": {
        "ok": { "const": false },
        "command": { "const": "list" },
        "schema_version": { "const": "prowl.cli.list.v1" },
        "error": {
          "type": "object",
          "additionalProperties": false,
          "required": ["code", "message"],
          "properties": {
            "code": {
              "type": "string",
              "enum": ["APP_NOT_RUNNING", "LIST_FAILED"]
            },
            "message": { "type": "string", "minLength": 1 },
            "details": { "$ref": "#/$defs/errorDetails" }
          }
        }
      }
    },
    "listResponse": {
      "oneOf": [
        { "$ref": "#/$defs/listSuccess" },
        { "$ref": "#/$defs/listError" }
      ]
    },

    "focusSuccess": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "data"],
      "properties": {
        "ok": { "const": true },
        "command": { "const": "focus" },
        "schema_version": { "const": "prowl.cli.focus.v1" },
        "data": {
          "type": "object",
          "additionalProperties": false,
          "required": ["requested", "resolved_via", "brought_to_front", "target"],
          "properties": {
            "requested": {
              "type": "object",
              "additionalProperties": false,
              "required": ["selector", "value"],
              "properties": {
                "selector": {
                  "type": "string",
                  "enum": ["worktree", "tab", "pane", "current"]
                },
                "value": {
                  "type": ["string", "null"]
                }
              },
              "allOf": [
                {
                  "if": {
                    "properties": { "selector": { "const": "current" } },
                    "required": ["selector"]
                  },
                  "then": {
                    "properties": {
                      "value": { "type": "null" }
                    }
                  }
                }
              ]
            },
            "resolved_via": {
              "type": "string",
              "enum": ["worktree", "tab", "pane"]
            },
            "brought_to_front": { "type": "boolean" },
            "target": { "$ref": "#/$defs/resolvedTarget" }
          }
        }
      }
    },
    "focusError": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "error"],
      "properties": {
        "ok": { "const": false },
        "command": { "const": "focus" },
        "schema_version": { "const": "prowl.cli.focus.v1" },
        "error": {
          "type": "object",
          "additionalProperties": false,
          "required": ["code", "message"],
          "properties": {
            "code": {
              "type": "string",
              "enum": [
                "APP_NOT_RUNNING",
                "INVALID_ARGUMENT",
                "TARGET_NOT_FOUND",
                "TARGET_NOT_UNIQUE",
                "FOCUS_FAILED"
              ]
            },
            "message": { "type": "string", "minLength": 1 },
            "details": { "$ref": "#/$defs/errorDetails" }
          }
        }
      }
    },
    "focusResponse": {
      "oneOf": [
        { "$ref": "#/$defs/focusSuccess" },
        { "$ref": "#/$defs/focusError" }
      ]
    },

    "sendSuccess": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "data"],
      "properties": {
        "ok": { "const": true },
        "command": { "const": "send" },
        "schema_version": { "const": "prowl.cli.send.v1" },
        "data": {
          "type": "object",
          "additionalProperties": false,
          "required": ["target", "input", "created_tab"],
          "properties": {
            "target": { "$ref": "#/$defs/resolvedTarget" },
            "input": {
              "type": "object",
              "additionalProperties": false,
              "required": ["source", "characters", "bytes", "trailing_enter_sent"],
              "properties": {
                "source": {
                  "type": "string",
                  "enum": ["argv", "stdin"]
                },
                "characters": {
                  "type": "integer",
                  "minimum": 1
                },
                "bytes": {
                  "type": "integer",
                  "minimum": 1
                },
                "trailing_enter_sent": { "type": "boolean" }
              }
            },
            "created_tab": { "type": "boolean" }
          }
        }
      }
    },
    "sendError": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "error"],
      "properties": {
        "ok": { "const": false },
        "command": { "const": "send" },
        "schema_version": { "const": "prowl.cli.send.v1" },
        "error": {
          "type": "object",
          "additionalProperties": false,
          "required": ["code", "message"],
          "properties": {
            "code": {
              "type": "string",
              "enum": [
                "APP_NOT_RUNNING",
                "INVALID_ARGUMENT",
                "TARGET_NOT_FOUND",
                "TARGET_NOT_UNIQUE",
                "EMPTY_INPUT",
                "SEND_FAILED"
              ]
            },
            "message": { "type": "string", "minLength": 1 },
            "details": { "$ref": "#/$defs/errorDetails" }
          }
        }
      }
    },
    "sendResponse": {
      "oneOf": [
        { "$ref": "#/$defs/sendSuccess" },
        { "$ref": "#/$defs/sendError" }
      ]
    },

    "keySuccess": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "data"],
      "properties": {
        "ok": { "const": true },
        "command": { "const": "key" },
        "schema_version": { "const": "prowl.cli.key.v1" },
        "data": {
          "type": "object",
          "additionalProperties": false,
          "required": ["requested", "key", "delivery", "target"],
          "properties": {
            "requested": {
              "type": "object",
              "additionalProperties": false,
              "required": ["token", "repeat"],
              "properties": {
                "token": { "type": "string", "minLength": 1 },
                "repeat": { "type": "integer", "minimum": 1, "maximum": 100 }
              }
            },
            "key": {
              "type": "object",
              "additionalProperties": false,
              "required": ["normalized", "category"],
              "properties": {
                "normalized": {
                  "type": "string",
                  "enum": [
                    "enter",
                    "esc",
                    "tab",
                    "backspace",
                    "up",
                    "down",
                    "left",
                    "right",
                    "pageup",
                    "pagedown",
                    "home",
                    "end",
                    "ctrl-c",
                    "ctrl-d",
                    "ctrl-l"
                  ]
                },
                "category": {
                  "type": "string",
                  "enum": ["navigation", "editing", "control"]
                }
              }
            },
            "delivery": {
              "type": "object",
              "additionalProperties": false,
              "required": ["attempted", "delivered", "mode"],
              "properties": {
                "attempted": { "type": "integer", "minimum": 1, "maximum": 100 },
                "delivered": { "type": "integer", "minimum": 1, "maximum": 100 },
                "mode": { "const": "keyDownUp" }
              }
            },
            "target": { "$ref": "#/$defs/resolvedTarget" }
          }
        }
      }
    },
    "keyError": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "error"],
      "properties": {
        "ok": { "const": false },
        "command": { "const": "key" },
        "schema_version": { "const": "prowl.cli.key.v1" },
        "error": {
          "type": "object",
          "additionalProperties": false,
          "required": ["code", "message"],
          "properties": {
            "code": {
              "type": "string",
              "enum": [
                "APP_NOT_RUNNING",
                "INVALID_ARGUMENT",
                "INVALID_REPEAT",
                "TARGET_NOT_FOUND",
                "TARGET_NOT_UNIQUE",
                "NO_ACTIVE_PANE",
                "UNSUPPORTED_KEY",
                "KEY_DELIVERY_FAILED"
              ]
            },
            "message": { "type": "string", "minLength": 1 },
            "details": { "$ref": "#/$defs/errorDetails" }
          }
        }
      }
    },
    "keyResponse": {
      "oneOf": [
        { "$ref": "#/$defs/keySuccess" },
        { "$ref": "#/$defs/keyError" }
      ]
    },

    "readSuccess": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "data"],
      "properties": {
        "ok": { "const": true },
        "command": { "const": "read" },
        "schema_version": { "const": "prowl.cli.read.v1" },
        "data": {
          "type": "object",
          "additionalProperties": false,
          "required": [
            "target",
            "mode",
            "last",
            "source",
            "truncated",
            "line_count",
            "text"
          ],
          "properties": {
            "target": { "$ref": "#/$defs/resolvedTarget" },
            "mode": {
              "type": "string",
              "enum": ["snapshot", "last"]
            },
            "last": {
              "type": ["integer", "null"],
              "minimum": 1
            },
            "source": {
              "type": "string",
              "enum": ["screen", "scrollback", "mixed"]
            },
            "truncated": { "type": "boolean" },
            "line_count": { "type": "integer", "minimum": 0 },
            "text": { "type": "string" }
          },
          "allOf": [
            {
              "if": {
                "properties": { "mode": { "const": "snapshot" } },
                "required": ["mode"]
              },
              "then": {
                "properties": {
                  "last": { "type": "null" }
                }
              }
            },
            {
              "if": {
                "properties": { "mode": { "const": "last" } },
                "required": ["mode"]
              },
              "then": {
                "properties": {
                  "last": { "type": "integer", "minimum": 1 }
                }
              }
            }
          ]
        }
      }
    },
    "readError": {
      "type": "object",
      "additionalProperties": false,
      "required": ["ok", "command", "schema_version", "error"],
      "properties": {
        "ok": { "const": false },
        "command": { "const": "read" },
        "schema_version": { "const": "prowl.cli.read.v1" },
        "error": {
          "type": "object",
          "additionalProperties": false,
          "required": ["code", "message"],
          "properties": {
            "code": {
              "type": "string",
              "enum": [
                "APP_NOT_RUNNING",
                "INVALID_ARGUMENT",
                "TARGET_NOT_FOUND",
                "TARGET_NOT_UNIQUE",
                "READ_FAILED"
              ]
            },
            "message": { "type": "string", "minLength": 1 },
            "details": { "$ref": "#/$defs/errorDetails" }
          }
        }
      }
    },
    "readResponse": {
      "oneOf": [
        { "$ref": "#/$defs/readSuccess" },
        { "$ref": "#/$defs/readError" }
      ]
    }
  }
}
```

## Usage notes

- Validate `prowl open --json` output against `#/$defs/openResponse`
- Validate `prowl list --json` output against `#/$defs/listResponse`
- Validate `prowl focus --json` output against `#/$defs/focusResponse`
- Validate `prowl send --json` output against `#/$defs/sendResponse`
- Validate `prowl key --json` output against `#/$defs/keyResponse`
- Validate `prowl read --json` output against `#/$defs/readResponse`

## Non-goals (v1)

- This file does **not** define CLI input argument parsing schemas.
- This file does **not** guarantee order-sensitive invariants that require runtime state checks across array items (for example, uniqueness of focused pane across all rows in `list`).
- This file does **not** attempt to encode transport-level details (stdout/stderr split, process exit code) beyond payload shape.
