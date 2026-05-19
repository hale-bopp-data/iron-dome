#!/usr/bin/env bash
# Iron Dome — Inline Credentials Guard
# Blocks commits that add inline credentials in URLs (https://user:pass@host).
#
# Origin: EasyWay S285/S297, PBI #1185. 25 .git/config server-side had PAT
# embedded in remote URLs — incident drove this preventive guard.
#
# Per-file diff scan: only added lines (^+), skip docs/placeholders.
# Escape hatch: INLINE_CREDS_SKIP=1

guard_inline_credentials() {
  local file="$1"

  if _is_whitelisted "inline_credentials" "$file"; then return 0; fi
  [[ "${INLINE_CREDS_SKIP:-}" == "1" ]] && return 0

  # Skip binary
  [[ "$file" =~ $IRON_DOME_BINARY_SKIP ]] && return 0
  # Skip iron-dome's own scripts (contain pattern as detection logic)
  [[ "$file" =~ iron-dome.*\.(sh|py)$ ]] && return 0
  [[ "$file" =~ git-hooks/(pre-commit|pre-push)$ ]] && return 0

  local pattern='https?://[^/[:space:]]*:[^@[:space:]]+@'
  local safe_re='(example\.com|placeholder|<REDACTED>|REDACTED|your[_-]?password|dummy|test-creds|TODO|FIXME|<[A-Z_][A-Z0-9_]*>)'

  local matches
  matches=$(git diff --cached -- "$file" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' | grep -iE "$pattern" 2>/dev/null || true)
  [[ -z "$matches" ]] && return 0

  local unsafe
  unsafe=$(echo "$matches" | grep -vE "$safe_re" 2>/dev/null || true)
  [[ -z "$unsafe" ]] && return 0

  _report_finding "INLINE_CREDS" "Inline credentials in URL" "$file" "1"
  IRON_DOME_OTHER_FOUND=$((IRON_DOME_OTHER_FOUND + 1))
  _guard_log "inline_credentials" "blocking" "$file: https://user:pass@host pattern detected"
  return 1
}
