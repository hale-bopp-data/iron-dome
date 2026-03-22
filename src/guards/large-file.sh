#!/usr/bin/env bash
# Iron Dome — Large File Guard
# Blocks commits of files exceeding a configurable size threshold.

guard_large_file() {
  local file="$1"
  local max_kb="${IRON_DOME_MAX_FILE_KB:-1024}"

  [[ ! -f "$file" ]] && return 0

  local size_bytes
  size_bytes=$(wc -c < "$file" 2>/dev/null || echo 0)
  local size_kb=$((size_bytes / 1024))

  # Check exclude patterns
  for excl in "${IRON_DOME_LARGE_FILE_EXCLUDE[@]}"; do
    if [[ "$file" == $excl ]]; then
      return 0
    fi
  done

  if [[ $size_kb -gt $max_kb ]]; then
    _report_finding "LARGE_FILE" "${size_kb}KB exceeds limit of ${max_kb}KB" "$file" "0"
    return 1
  fi

  return 0
}
