#!/usr/bin/env bash
#
# scripts/sync.sh — pull the parent repo and both submodules to their origin HEAD.
#
# - Parent (chatbot): fast-forward pull from origin on the current branch.
# - Submodules (backend, frontend): fast-forward pull from origin/main, but only when
#   the submodule is currently on the `main` branch. Feature branches and detached HEAD
#   are skipped so in-progress work is never disturbed.
# - Uses --ff-only everywhere; divergent local history aborts instead of merging.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pull_dir() {
  local label="$1"
  local path="$2"
  local require_branch="${3:-}"

  printf '\n→ %s\n' "$label"

  cd "$path" || { echo "  ✗ cannot enter $path"; return 1; }

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    echo "  ⚠ detached HEAD — skipping"
    return 0
  fi

  if [ -n "$require_branch" ] && [ "$branch" != "$require_branch" ]; then
    echo "  ⚠ on '$branch', expected '$require_branch' — skipping (run 'git switch $require_branch' first)"
    return 0
  fi

  if git pull --ff-only origin "$branch"; then
    return 0
  fi

  echo "  ✗ pull failed"
  return 1
}

failures=0
pull_dir "Parent (chatbot)"     "$REPO_ROOT"               || failures=$((failures + 1))
pull_dir "Submodule: backend"   "$REPO_ROOT/backend"  main || failures=$((failures + 1))
pull_dir "Submodule: frontend"  "$REPO_ROOT/frontend" main || failures=$((failures + 1))

echo
if [ "$failures" -gt 0 ]; then
  echo "✗ Sync finished with $failures failure(s)"
  exit 1
fi
echo "✓ Sync complete"
