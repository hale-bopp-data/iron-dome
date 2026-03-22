#!/usr/bin/env bash
# Iron Dome — Docker Run Guard
# Enforces "compose only" policy. Blocks docker run in scripts.

guard_docker_run() {
  local file="$1"

  # Only check script files
  if ! [[ "$file" =~ \.(sh|bash|ps1|psm1|py|yml|yaml)$ ]]; then
    return 0
  fi

  local found=0

  # Grep for docker run, exclude comments
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP 'docker\s+run\b' "$file" 2>/dev/null | LC_ALL=en_US.UTF-8 grep -vP '^\d+:\s*#' | LC_ALL=en_US.UTF-8 grep -vP '^\d+:\s*//' || true)
  [[ -z "$matches" ]] && return 0

  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "DOCKER_RUN" "Use 'docker compose' instead" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
