#!/usr/bin/env bash
# Iron Dome — Conflict Markers Guard
# Blocks files containing unresolved merge conflict markers.

guard_conflict_markers() {
  local file="$1"
  local found=0

  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP '^(<{7}|>{7}|={7})( |$)' "$file" 2>/dev/null || true)
  [[ -z "$matches" ]] && return 0

  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "CONFLICT_MARKER" "Unresolved merge conflict" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
