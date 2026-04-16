#!/usr/bin/env bash
# Iron Dome — AB# ↔ Branch match guard (advisory, non-blocking)
#
# Warns when the commit message references AB#N (an Azure DevOps work item)
# whose number does not match the numeric prefix of the current branch name.
#
# Rationale: during WIP sessions with multiple worktrees, it is easy to commit
# a fix for AB#1243 on a branch called `feat/1242-...`. The work looks merged
# from the PBI's perspective but the commit ends up orphaned on the wrong branch.
# By the time anyone notices, the branch has diverged and the commit is lost.
# This guard catches the mismatch at commit time, when it's still cheap to fix.
#
# Behaviour:
#   - 0 AB#N references in message  -> silent skip
#   - branch is main/master/develop -> silent skip
#   - branch does not match feat|fix|chore|docs|refactor|hotfix/<n>-...
#     -> silent skip (we can't infer intent)
#   - at least one AB#N matches the branch number -> silent pass
#   - no AB#N matches the branch number -> WARN on stderr, exit 0 (NEVER blocks)
#
# Hook: commit-msg. Called with the commit-message file path as $1.
guard_ab_match() {
  local msg_file="$1"
  [[ -z "$msg_file" || ! -f "$msg_file" ]] && return 0

  # Extract AB#N references (dedup). grep -o emits one match per line.
  local ab_numbers
  ab_numbers=$(grep -oE '\bAB#[0-9]+\b' "$msg_file" 2>/dev/null | sed 's/AB#//' | sort -u || true)
  [[ -z "$ab_numbers" ]] && return 0

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')
  [[ -z "$branch" || "$branch" == "HEAD" ]] && return 0

  # Skip protected / non-PBI branches
  case "$branch" in
    main|master|develop|release|release/*) return 0 ;;
  esac

  # Extract numeric prefix from branch: feat/1305-foo -> 1305
  local branch_num
  branch_num=$(echo "$branch" | grep -oE '^(feat|fix|chore|docs|refactor|hotfix)/[0-9]+' | grep -oE '[0-9]+$' || true)
  [[ -z "$branch_num" ]] && return 0

  # Any AB#N matches branch_num?
  local matched=false
  local ab
  for ab in $ab_numbers; do
    if [[ "$ab" == "$branch_num" ]]; then
      matched=true
      break
    fi
  done

  if [[ "$matched" == false ]]; then
    local ab_list
    ab_list=$(echo "$ab_numbers" | paste -sd ',' -)
    echo "" >&2
    echo "[IRON-DOME AB-MISMATCH] advisory (non-blocking):" >&2
    echo "  commit references AB#${ab_list} but branch is '${branch}' (number=${branch_num})." >&2
    echo "  If intentional (e.g. cross-PBI reference), ignore." >&2
    echo "  If not, abort (Ctrl-C), fix the message with 'git commit --amend', or switch branch." >&2
    echo "" >&2
    IRON_DOME_ADVISORY_FOUND=$((IRON_DOME_ADVISORY_FOUND + 1))
    if type _guard_log &>/dev/null; then
      _guard_log "ab_match" "advisory" "commit AB#${ab_list} vs branch ${branch}"
    fi
  fi

  return 0
}
