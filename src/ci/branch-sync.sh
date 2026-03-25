#!/usr/bin/env bash
# Iron Dome CI — Branch Sync Check
# Verifies that a PR branch is not too far behind its target branch.
# Stale branches cause merge conflicts and integration drift.
#
# Usage: branch-sync.sh [target-branch] [max-behind]
#   Defaults: target=main, max-behind=50
#
# Exit: 0 = in sync, 1 = too far behind
# PBI #517 — S184

set -euo pipefail

TARGET="${1:-main}"
MAX_BEHIND="${2:-50}"

# Ensure we have the target branch refs
git fetch origin "$TARGET" --quiet 2>/dev/null || true

CURRENT=$(git branch --show-current 2>/dev/null || echo "detached")
BEHIND=$(git rev-list --count "HEAD..origin/${TARGET}" 2>/dev/null || echo "0")

echo "Iron Dome CI: Branch Sync Check"
echo "  Branch:  $CURRENT"
echo "  Target:  $TARGET"
echo "  Behind:  $BEHIND commit(s)"
echo "  Max:     $MAX_BEHIND"

if [[ "$BEHIND" -gt "$MAX_BEHIND" ]]; then
  echo ""
  echo "  BLOCKED: branch is $BEHIND commits behind origin/$TARGET (max $MAX_BEHIND)."
  echo "  Rebase or merge target into your branch before PR."
  echo ""
  echo "  Fix:  git fetch origin $TARGET && git merge origin/$TARGET"
  exit 1
fi

if [[ "$BEHIND" -gt 0 ]]; then
  echo "  Advisory: $BEHIND commits behind (within threshold)."
else
  echo "  Branch is up to date with origin/$TARGET."
fi

exit 0
