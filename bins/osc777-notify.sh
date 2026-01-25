#!/usr/bin/env bash
set -euo pipefail

title=${1:-"Title"}
body=${2:-"Body"}
printf '\033]777;notify;%s;%s\a' "$title" "$body"
