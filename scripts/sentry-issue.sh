#!/usr/bin/env bash
# Fetch a Sentry issue and print a compact, agent-friendly markdown summary.
#
# Usage:
#   scripts/sentry-issue.sh <issue_id_or_url>
#
# Auth:
#   Reads SENTRY_AUTH_TOKEN from env, or [auth]token=... from ~/.sentryclirc.
#   Optional: SENTRY_URL (defaults to https://sentry.io).
#
# Requires: curl, jq.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <issue_id_or_url>" >&2
  exit 64
fi

arg="$1"
if [[ "$arg" =~ /issues/([0-9]+) ]]; then
  issue_id="${BASH_REMATCH[1]}"
elif [[ "$arg" =~ ^[0-9]+$ ]]; then
  issue_id="$arg"
else
  echo "error: cannot parse issue id from '$arg'" >&2
  exit 65
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 69
fi

token="${SENTRY_AUTH_TOKEN:-}"
if [ -z "$token" ] && [ -f "$HOME/.sentryclirc" ]; then
  token=$(awk '
    /^\[auth\]/      { in_auth = 1; next }
    /^\[/            { in_auth = 0 }
    in_auth && /^[[:space:]]*token[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/"/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$HOME/.sentryclirc")
fi

if [ -z "$token" ]; then
  echo "error: no token. Set SENTRY_AUTH_TOKEN or write [auth]\\ntoken=... to ~/.sentryclirc" >&2
  exit 77
fi

base_url="${SENTRY_URL:-https://sentry.io}"
api="${base_url%/}/api/0"
auth_header="Authorization: Bearer $token"

fetch() {
  local url="$1"
  local body
  body=$(curl -sS -H "$auth_header" -w "\n%{http_code}" "$url")
  local status="${body##*$'\n'}"
  local payload="${body%$'\n'*}"
  if [ "$status" != "200" ]; then
    echo "error: $url returned HTTP $status" >&2
    echo "$payload" | jq -r '.detail // .' >&2 2>/dev/null || echo "$payload" >&2
    exit 1
  fi
  printf '%s' "$payload"
}

issue_json=$(fetch "$api/issues/$issue_id/")
event_json=$(fetch "$api/issues/$issue_id/events/latest/")

# --- Issue summary ---
echo "# Sentry Issue $issue_id"
echo
echo "$issue_json" | jq -r '
  "**title**: \(.title // "<unknown>")",
  "**status**: \(.status // "?") / **level**: \(.level // "?") / **platform**: \(.platform // "?")",
  "**count**: \(.count // "0") events / **userCount**: \(.userCount // "0") users",
  "**firstSeen**: \(.firstSeen // "?")",
  "**lastSeen**: \(.lastSeen // "?")",
  "**permalink**: \(.permalink // "?")"
'

# --- Tags (top 20) ---
echo
echo "## Tags"
echo "$event_json" | jq -r '.tags // [] | .[0:20] | .[] | "- **\(.key)**: \(.value)"'

# --- Exception ---
echo
echo "## Exception"
echo "$event_json" | jq -r '
  ((.entries // []) | map(select(.type == "exception")) | .[0].data.values // []) as $vals
  | if ($vals | length) == 0 then "(no exception entry — may be a message or hang event)"
    else
      $vals[] | "- **type**: \(.type // "?")\n  **value**: \(.value // "")\n  **module**: \(.module // "?")"
    end
'

# --- Stack trace (topmost frame first, up to 30) ---
echo
echo "## Stack Trace (topmost first, up to 30 frames)"
echo "$event_json" | jq -r '
  ((.entries // []) | map(select(.type == "exception")) | .[0].data.values // []) as $vals
  | if ($vals | length) == 0 then "(no stacktrace)"
    else
      ($vals[-1].stacktrace.frames // []) as $frames
      | $frames | reverse | .[0:30] | to_entries[]
      | "\(.key | tostring | .[0:3])  \(.value.function // "<?>")  @  \(.value.filename // .value.absPath // .value.module // "<?>"):\(.value.lineNo // "?")  \(if (.value.inApp // false) then "[app]" else "" end)"
    end
'

# --- Breadcrumbs (last 50, oldest → newest so the crash sits at the bottom) ---
echo
echo "## Breadcrumbs (last 50, oldest first)"
echo "$event_json" | jq -r '
  ((.entries // []) | map(select(.type == "breadcrumbs")) | .[0].data.values // []) as $bc
  | if ($bc | length) == 0 then "(no breadcrumbs)"
    else
      ($bc | .[-50:] | .[]
       | "[\(.timestamp // "?")] \(.category // "?") (\(.level // "info")): \(.message // (.data | tostring))"
      )
    end
'

# --- Selected contexts (app / device / os / runtime) ---
echo
echo "## Context"
echo "$event_json" | jq -r '
  (.contexts // {}) as $ctx
  | ["app", "device", "os", "runtime"]
  | .[] as $key
  | if ($ctx[$key] // null) == null then empty
    else
      "### \($key)\n" +
      ($ctx[$key] | to_entries | map("  \(.key): \(.value)") | join("\n"))
    end
'
