#!/usr/bin/env bash
# Iron Dome — Path Length Guard
# Blocks files with paths exceeding Windows MAX_PATH (260 characters).
# Cross-platform projects break silently when paths are too long on Windows.
#
# PBI #516 — S184

IRON_DOME_MAX_PATH=${IRON_DOME_MAX_PATH:-260}

guard_path_length() {
  local file="$1"
  local len=${#file}

  if [[ $len -ge $IRON_DOME_MAX_PATH ]]; then
    _report_finding "path-length" "$file" "Path too long (${len} chars, max ${IRON_DOME_MAX_PATH}) — will fail on Windows"
    IRON_DOME_OTHER_FOUND=$((IRON_DOME_OTHER_FOUND + 1))
    _guard_log "path-length" "blocking" "$file: ${len} chars (max ${IRON_DOME_MAX_PATH})"
    return 1
  fi

  return 0
}
