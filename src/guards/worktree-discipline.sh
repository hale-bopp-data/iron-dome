#!/usr/bin/env bash
# Iron Dome — Worktree Discipline Guard (G28)
# Blocks commits from base clone on feature branches.
# Feature work REQUIRES a worktree (isolation + cross-agent safety).
#
# Origin: EasyWay S519/S520, PBI #1364. Cross-agent enforced.
#
# Worktree detection: .git is a FILE in worktrees (vs directory in base clone).
#
# Escape hatch: WORKTREE_SKIP=1 or G28_SKIP=1

# Per-file: no-op (gate is repo-level, called once via _finalize)
guard_worktree_discipline() { return 0; }

guard_worktree_discipline_finalize() {
  [[ "${WORKTREE_SKIP:-${G28_SKIP:-}}" == "1" ]] && { echo "SKIP Worktree Discipline Guard skipped (WORKTREE_SKIP=1)"; return 0; }

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  [[ -z "$branch" ]] && return 0

  # Only feature branches (configurable prefixes)
  local feature_prefixes="${WORKTREE_FEATURE_PREFIXES:-^(feat|fix|docs|refactor|chore|test)/}"
  if [[ ! "$branch" =~ $feature_prefixes ]]; then
    echo "OK Worktree Discipline Guard passed (not a feature branch)."
    return 0
  fi

  # Worktree detection: in a linked worktree, the top-level `.git` is a FILE
  # (pointer to the gitdir under the main repo's `.git/worktrees/`). In a base
  # clone, `.git` is a directory. The previous check used `git rev-parse
  # --git-dir` which always returns a directory path (worktree gitdir under
  # main, or `.git` in base clone) — `-f` would always be false → false-positive
  # block on legitimate worktree commits. Bug #2153 (S101): use toplevel `.git`
  # type as the discriminator.
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [[ -n "$top" && -f "$top/.git" ]]; then
    echo "OK Worktree Discipline Guard passed (worktree detected)."
    return 0
  fi

  echo ""
  echo "BLOCKED: Worktree Discipline Guard (G28)"
  echo "  Branch '$branch' is a feature branch on the base clone."
  echo "  Feature work REQUIRES a worktree (isolation + cross-agent safety)."
  echo ""
  echo "  Fix:"
  echo "     git worktree add ../wt-$(echo $branch | tr '/' '-') $branch"
  echo ""
  echo "  Bypass: WORKTREE_SKIP=1 git commit"
  _guard_log "worktree_discipline" "blocking" "commit from base clone on $branch"
  return 1
}
