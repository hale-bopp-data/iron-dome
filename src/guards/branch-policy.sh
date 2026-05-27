#!/usr/bin/env bash
# Iron Dome — Branch Policy Guard
# Blocks direct push to protected branches. No exceptions. No discretion.
#
# Reads protected branches from iron-dome.yml or defaults to main/master.

guard_branch_policy() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  [[ -z "$branch" ]] && return 0

  # Escape hatch
  if [[ "${IRON_DOME_BRANCH_SKIP:-}" == "1" ]]; then
    echo "  WARNING: Branch policy BYPASSED by IRON_DOME_BRANCH_SKIP=1"
    _guard_log "branch-policy" "bypass" "IRON_DOME_BRANCH_SKIP=1 on $branch"
    return 0
  fi

  # Default protected branches
  local protected=("main" "master")
  if [[ ${#IRON_DOME_PROTECTED_BRANCHES[@]} -gt 0 ]]; then
    protected=("${IRON_DOME_PROTECTED_BRANCHES[@]}")
  fi

  for pb in "${protected[@]}"; do
    if [[ "$branch" == "$pb" ]]; then
      echo ""
      echo "  BLOCKED: push to '$branch' is not allowed"
      echo ""
      echo "  '$branch' is a protected branch (Iron Dome branch policy)."
      echo "  Direct push to protected branches is prohibited."
      echo ""
      echo "  How to proceed:"
      echo "    1. Create a feature branch:  git checkout -b feat/my-change"
      echo "    2. Push the feature branch:  git push origin feat/my-change"
      echo "    3. Create a Pull Request"
      echo ""
      echo "  Emergency bypass (logged): IRON_DOME_BRANCH_SKIP=1 git push"
      echo ""
      _guard_log "branch-policy" "blocking" "direct push to '$branch' BLOCKED"
      return 1
    fi
  done

  return 0
}
