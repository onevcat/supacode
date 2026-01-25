#!/usr/bin/env bash
set -euo pipefail

body=${1:-"Hello from OSC 9"}
printf '\033]9;%s\a' "$body"
