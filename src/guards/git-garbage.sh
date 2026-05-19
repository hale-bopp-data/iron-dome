#!/usr/bin/env bash
# Iron Dome — Git Garbage Guard
# Detects accidental git output (git status, git diff headers) baked into content files.
# Root cause: redirect like `git status > file.md`.
# Auto-fixes: strips garbage lines, re-stages the cleaned file.
#
# Origin: EasyWay S242 — recurring documentation pollution pattern.

guard_git_garbage() {
  local file="$1"

  if _is_whitelisted "git_garbage" "$file"; then return 0; fi

  # Only text content files (md, txt, json, yml)
  [[ ! "$file" =~ \.(md|txt|json|yml|yaml)$ ]] && return 0

  local pattern='^(Your branch is up to date|Changes to be committed|Changes not staged|Untracked files:|On branch [a-z]|  \(use "git |	modified:|	new file:|	deleted:|	renamed:|Dropped refs/stash)'

  if ! grep -qE "$pattern" "$file" 2>/dev/null; then return 0; fi

  local count
  count=$(grep -cE "$pattern" "$file" 2>/dev/null || echo 0)

  # Auto-fix: strip garbage + re-stage
  grep -vE "$pattern" "$file" > "${file}.clean" 2>/dev/null
  sed -i '/./,$!d' "${file}.clean" 2>/dev/null || true
  mv "${file}.clean" "$file"
  git add "$file"

  echo "AUTO-FIX: Git Garbage Guard removed $count garbage lines from $file"
  _guard_log "git_garbage" "auto-fix" "$file: $count lines cleaned"
  return 0
}
