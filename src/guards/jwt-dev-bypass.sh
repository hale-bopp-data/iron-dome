#!/usr/bin/env bash
# Iron Dome Guard: JWT / Auth Dev Bypass in Production Code
# Hook: pre-commit
# Default: ON
#
# Detects patterns where authentication is disabled based on NODE_ENV
# or similar environment flags. These are the #1 cause of auth bypass
# in production when env vars are misconfigured.
#
# GEDI: "La vittoria si ottiene prima della battaglia" — catch dev bypass
# before it reaches production, not after the breach.

guard_jwt_dev_bypass() {
  local file="$1"

  case "$file" in
    *.js|*.mjs|*.cjs|*.ts|*.mts) ;;
    *) return 0 ;;
  esac

  if _is_whitelisted "jwt_dev_bypass" "$file"; then return 0; fi

  local found=0

  # Pattern 1: NODE_ENV === "development" used to skip auth/return early
  local p1='NODE_ENV\s*[=!]==?\s*["\x27]development["\x27]'
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p1" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    # Only flag if near auth-related keywords (within same line)
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qiP '(auth|jwt|token|session|login|bypass|skip|mock|fake|dev.user)' 2>/dev/null; then
      local line_num="${match_line%%:*}"
      _report_finding "AUTH_BYPASS" "NODE_ENV dev check near auth logic" "$file" "$line_num"
      found=$((found + 1))
    fi
  done <<< "$matches"

  # Pattern 2: DB_MODE === "mock" disabling auth
  local p2='DB_MODE\s*[=!]==?\s*["\x27]mock["\x27]'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p2" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qiP '(auth|jwt|token|session|user|bypass|skip|next\(\))' 2>/dev/null; then
      local line_num="${match_line%%:*}"
      _report_finding "AUTH_BYPASS" "DB_MODE mock check near auth logic" "$file" "$line_num"
      found=$((found + 1))
    fi
  done <<< "$matches"

  # Pattern 3: Hardcoded dev-user / test-user in auth middleware
  local p3='(sub|userId|user_id)\s*[:=]\s*["\x27](dev-user|test-user|admin|root)["\x27]'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p3" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    if _is_safe_match "${match_line#*:}"; then continue; fi
    local line_num="${match_line%%:*}"
    _report_finding "AUTH_BYPASS" "Hardcoded dev/test user identity" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
