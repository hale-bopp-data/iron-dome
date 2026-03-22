#!/usr/bin/env bash
# Iron Dome — Debt Guard (advisory)
# Tracks new TODO/FIXME/HACK introduced in staged files.
# Never blocks — only logs to telemetry.

guard_debt() {
  local file="$1"

  # Skip non-code files
  if [[ "$file" =~ \.(md|txt|log|csv|json|yml|yaml)$ ]]; then
    return 0
  fi

  local found=0
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nPw 'TODO|FIXME|HACK|XXX|TEMP|WORKAROUND' "$file" 2>/dev/null || true)
  [[ -z "$matches" ]] && return 0

  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    local line_content="${match_line#*:}"

    # Determine which keyword
    local kw="DEBT"
    for k in TODO FIXME HACK XXX TEMP WORKAROUND; do
      if echo "$line_content" | grep -qw "$k" 2>/dev/null; then
        kw="$k"
        break
      fi
    done

    _report_finding "DEBT" "$kw marker found" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
