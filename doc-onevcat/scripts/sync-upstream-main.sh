#!/usr/bin/env bash
set -euo pipefail

TARGET_BRANCH="${1:-main}"

echo "[sync] fetch remotes"
git fetch origin upstream --prune

echo "[sync] switch to ${TARGET_BRANCH}"
git switch "${TARGET_BRANCH}"

echo "[sync] fast-forward from origin/${TARGET_BRANCH}"
git pull --ff-only origin "${TARGET_BRANCH}"

echo "[sync] merge upstream/main into ${TARGET_BRANCH}"
git merge --no-ff upstream/main

echo "[sync] verify build"
make build-app

echo
echo "[done] upstream merged into ${TARGET_BRANCH}"
echo "Next recommended steps:"
echo "  1) make test"
echo "  2) git push origin ${TARGET_BRANCH}"
