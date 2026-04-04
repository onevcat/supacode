#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <xcresult-path>" >&2
  exit 0
fi

result_bundle="$1"

if [ ! -d "$result_bundle" ]; then
  echo "warning: xcresult bundle not found at $result_bundle"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "warning: jq is required to parse xcresult summary details"
  exit 0
fi

summary_json="$(mktemp)"
cleanup() {
  rm -f "$summary_json"
}
trap cleanup EXIT

if ! xcrun xcresulttool get test-results summary --path "$result_bundle" --compact >"$summary_json" 2>/dev/null; then
  echo "warning: failed to parse xcresult summary from $result_bundle"
  exit 0
fi

failed_tests="$(
  jq -r '
    if (.failedTests? | type) == "number" then .failedTests
    elif (.failedTests? | type) == "string" then (.failedTests | tonumber? // 0)
    else 0
    end
  ' "$summary_json"
)"

if [ "$failed_tests" -eq 0 ]; then
  echo "No failed tests found in xcresult summary."
  exit 0
fi

echo
echo "================ xcresult failure details ================"

jq -r '
  (.testFailures // []) as $failures
  | if ($failures | length) == 0 then
      "warning: summary has failedTests=\(.failedTests // "unknown"), but no testFailures entries were found."
    else
      $failures[]
      | "test: \(.testName // "unknown")",
        "target: \(.targetName // "unknown")",
        "identifier: \(.testIdentifierString // "n/a")",
        ("failure: " + ((.failureText // "n/a") | gsub("\\n"; "\n         "))),
        ""
    end
' "$summary_json"

echo "=========================================================="
