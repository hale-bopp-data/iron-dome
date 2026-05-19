#!/usr/bin/env bash
# Iron Dome — Encoding Guard
# Detects files with BOM (Byte Order Mark) or non-UTF-8 encoding.
# BOM causes subtle bugs in shell scripts, YAML, JSON, and CI pipelines.
#
# PBI #515 — S184

guard_encoding() {
  local file="$1"

  # Only check text files (skip binary via extension)
  [[ "$file" =~ $IRON_DOME_BINARY_SKIP ]] && return 0

  # Check for UTF-8 BOM (EF BB BF) — first 3 bytes
  local hex
  hex=$(xxd -l 3 -p "$file" 2>/dev/null || true)

  if [[ "$hex" == "efbbbf" ]]; then
    _report_finding "encoding" "UTF-8 BOM detected — remove BOM (can break shell/YAML/JSON)" "$file" "1"
    IRON_DOME_OTHER_FOUND=$((IRON_DOME_OTHER_FOUND + 1))
    _guard_log "encoding" "blocking" "$file: UTF-8 BOM"
    return 1
  fi

  # Check for UTF-16 BOM (FF FE or FE FF)
  local hex2
  hex2=$(xxd -l 2 -p "$file" 2>/dev/null || true)

  if [[ "$hex2" == "fffe" || "$hex2" == "feff" ]]; then
    _report_finding "encoding" "UTF-16 BOM detected — convert to UTF-8" "$file" "1"
    IRON_DOME_OTHER_FOUND=$((IRON_DOME_OTHER_FOUND + 1))
    _guard_log "encoding" "blocking" "$file: UTF-16 BOM"
    return 1
  fi

  return 0
}
