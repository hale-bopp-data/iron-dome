#!/usr/bin/env bash
# Iron Dome Guard: CORS Wildcard / Misconfiguration
# Hook: pre-commit
# Default: ON
#
# Detects dangerous CORS configurations:
# - origin: "*" with credentials (browser ignores, but signals bad config)
# - Access-Control-Allow-Origin: * in server config
# - Reflecting origin without validation
#
# GEDI Testudo: "C'e' un punto debole dove gli scudi non si toccano?"

guard_cors_wildcard() {
  local file="$1"

  case "$file" in
    *.js|*.mjs|*.cjs|*.ts|*.mts|*.json|*.yml|*.yaml|*Caddyfile*|*.conf|*.nginx) ;;
    *) return 0 ;;
  esac

  if _is_whitelisted "cors_wildcard" "$file"; then return 0; fi

  local found=0

  # Pattern 1: cors({ origin: "*" }) or cors({ origin: true }) — accepts all origins
  local p1='cors\s*\(\s*\{[^}]*(origin\s*:\s*(\*|true|"\*"))'
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p1" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "CORS" "CORS origin wildcard or true (accepts all origins)" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 2: Access-Control-Allow-Origin: * in headers/config
  local p2='Access-Control-Allow-Origin\s*[:=]\s*["\x27]?\*'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p2" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    # Skip comments
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '^\s*(#|//)' 2>/dev/null; then continue; fi
    local line_num="${match_line%%:*}"
    _report_finding "CORS" "Access-Control-Allow-Origin: * header" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 3: Reflecting req.headers.origin without validation
  local p3='req\.(headers\.origin|get\(["\x27]origin["\x27]\))\s*[^;]*Access-Control|origin\s*:\s*req\.'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p3" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "CORS" "Reflecting request origin without validation" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
