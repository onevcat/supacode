#!/usr/bin/env bash
set -euo pipefail

TARGET_BRANCH="${1:-main}"

die() {
  echo "[error] $*" >&2
  exit 1
}

ensure_remote_exists() {
  local remote_name="$1"
  git remote get-url "${remote_name}" >/dev/null 2>&1 || die "missing git remote: ${remote_name}"
}

ensure_clean_worktree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "working tree is not clean. commit or stash your changes before syncing."
  fi
}

ensure_remote_branch_exists() {
  local remote_name="$1"
  local branch_name="$2"
  git show-ref --verify --quiet "refs/remotes/${remote_name}/${branch_name}" || \
    die "remote branch not found: ${remote_name}/${branch_name}"
}

echo "[sync] preflight checks"
ensure_clean_worktree
ensure_remote_exists origin
ensure_remote_exists upstream

echo "[sync] fetch remotes"
git fetch origin --prune
git fetch upstream --prune
ensure_remote_branch_exists origin "${TARGET_BRANCH}"
ensure_remote_branch_exists upstream "main"

echo "[sync] switch to ${TARGET_BRANCH}"
git switch "${TARGET_BRANCH}"

echo "[sync] fast-forward from origin/${TARGET_BRANCH} (deterministic merge-based flow)"
git merge --ff-only "origin/${TARGET_BRANCH}"

echo "[sync] merge upstream/main into ${TARGET_BRANCH}"
git merge --no-ff upstream/main

echo "[sync] verify build"
make build-app

echo
echo "[done] upstream merged into ${TARGET_BRANCH}"
echo "Next recommended steps:"
echo "  1) make test"
echo "  2) git push origin ${TARGET_BRANCH}"
