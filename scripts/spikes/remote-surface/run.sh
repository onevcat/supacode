#!/usr/bin/env bash
set -euo pipefail
spike_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$spike_dir/../../.." && pwd)"
output_dir="${1:?Usage: run.sh BUILD_DIRECTORY [EVIDENCE_DIRECTORY]}"
evidence_dir="${2:-$(mktemp -d /tmp/prowl-remote-evidence.XXXXXX)}"
mkdir -p "$evidence_dir"
evidence_dir="$(cd "$evidence_dir" && pwd)"
export GHOSTTY_RESOURCES_DIR="$repo_dir/ThirdParty/ghostty/zig-out/share/ghostty"
"$output_dir/Remote Surface Spike.app/Contents/MacOS/spike" \
  "$spike_dir" "$evidence_dir" "$(command -v python3)" > "$evidence_dir/runtime.log" 2>&1
python3 "$spike_dir/verify.py" "$evidence_dir"
