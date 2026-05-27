#!/usr/bin/env bash
# Iron Dome — WI-Link Guard (G26)
# Auto-prepends work item reference (e.g. #1234) to commit messages
# when the branch name contains a WI number.
#
# Origin: EasyWay S462/S464, PBI #1647/#1649.
# Generic: works with any "#NNN" or "AB#NNN" convention.
#
# This guard runs as a PRE-FILE no-op + a finalize step in pre-commit
# (called separately from the orchestrator after STAGED_FILES iteration).

# Per-file: no-op (kept to satisfy uniform guard_<name> contract).
guard_wi_link() { return 0; }

# Pre-commit finalize hook: auto-prepend if applicable.
# Called explicitly by src/hooks/pre-commit before exit.
guard_wi_link_finalize() {
  [[ "${WI_LINK_SKIP:-${G26_SKIP:-}}" == "1" ]] && { echo "SKIP WI-Link Guard skipped (WI_LINK_SKIP=1)"; return 0; }

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  [[ -z "$branch" ]] && return 0

  local wi
  wi=$(echo "$branch" | grep -oP '(?:PBI|Bug|Epic|Task)[/-]?\K\d{3,5}' 2>/dev/null || true)
  if [[ -z "$wi" ]]; then
    wi=$(echo "$branch" | grep -oP '(?:^|[^0-9])\K\d{3,5}(?=[^0-9]|$)' 2>/dev/null || true)
  fi
  [[ -z "$wi" ]] && { echo "OK WI-Link Guard passed (no WI in branch name)."; return 0; }

  local msg_file
  msg_file="$(git rev-parse --git-dir 2>/dev/null)/COMMIT_EDITMSG"
  [[ ! -f "$msg_file" ]] && { echo "WI-Link Guard: commit message file not found, cannot auto-prepend WI #$wi"; return 0; }

  local msg
  msg=$(cat "$msg_file" 2>/dev/null || echo "")

  # Staleness detection: same-as-previous-commit
  if [[ -n "$msg" ]]; then
    local prev
    prev=$(git log -1 --format="%s" 2>/dev/null || echo "")
    [[ "$msg" == "$prev" ]] && msg=""
  fi

  local wi_in_msg
  wi_in_msg=$(echo "$msg" | grep -oP '(?:#|AB#)\d{3,5}' 2>/dev/null | head -1 || true)

  # Cross-branch staleness: WI in msg != branch WI
  if [[ -n "$wi_in_msg" ]]; then
    local in_num
    in_num=$(echo "$wi_in_msg" | grep -oP '\d{3,5}' || true)
    if [[ "$in_num" != "$wi" ]]; then
      echo "WI-Link Guard WARN: COMMIT_EDITMSG has WI #$in_num but branch expects #$wi (stale). Using branch WI."
      wi_in_msg=""
    fi
  fi

  if [[ -z "$wi_in_msg" ]]; then
    local prefix="#${wi} - "
    local content
    content=$(cat "$msg_file" 2>/dev/null || echo "")
    echo "${prefix}${content}" > "$msg_file"
    echo "WI-Link AUTO-FIX: Prepended #${wi} - to commit message (from branch '$branch')"
    _guard_log "wi_link" "auto-fix" "prepended #${wi} from branch=$branch"
  else
    echo "OK WI-Link Guard: WI ${wi_in_msg} found in commit message."
  fi
}
