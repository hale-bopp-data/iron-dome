#!/usr/bin/env bash
# Iron Dome — Secrets Scan Guard
# Detects hardcoded secrets in staged/changed files using regex.
# The Dumb Guard: no AI, no LLM — pure pattern matching.
#
# Performance: uses grep -nP per file per pattern (not line-by-line).

guard_secrets() {
  local file="$1"
  local found=0

  for entry in "${IRON_DOME_SECRET_PATTERNS[@]}"; do
    local name="${entry%%|||*}"
    local pattern="${entry##*|||}"

    # Check if disabled
    if _is_pattern_disabled "$name"; then
      continue
    fi

    # Single grep call per pattern per file — fast
    local matches
    matches=$(LC_ALL=en_US.UTF-8 grep -nP "$pattern" "$file" 2>/dev/null || true)
    [[ -z "$matches" ]] && continue

    # Check each match against safe patterns
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      local line_num="${match_line%%:*}"
      local line_content="${match_line#*:}"

      if _is_safe_match "$line_content"; then
        continue
      fi

      _report_finding "SECRET" "$name" "$file" "$line_num"
      found=$((found + 1))
    done <<< "$matches"
  done

  return $found
}
