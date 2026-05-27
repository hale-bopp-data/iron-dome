#!/usr/bin/env bash
# Iron Dome — Anti-Hardcoded Audit Guard (Presa Elettrica)
# Detects hardcoded paths/values that should be variables or config.
#
# Origin: EasyWay G16 "Presa Elettrica" — standard interface, any consumer.
# Hardcoded path = the device is not a presa elettrica.
#
# Patterns flagged (advisory, non-blocking by default):
# - Absolute Windows paths (C:\..., D:\...)
# - Absolute UNIX paths (/c/EW/..., /opt/easyway/...)
# - User-specific paths (/home/<user>/, C:\Users\<user>\)
#
# Configurable via env: ANTI_HARDCODED_BLOCKING=1 to upgrade to blocking.
# Escape hatch: ANTI_HARDCODED_SKIP=1

guard_anti_hardcoded() {
  local file="$1"

  if _is_whitelisted "anti_hardcoded" "$file"; then return 0; fi
  [[ "${ANTI_HARDCODED_SKIP:-}" == "1" ]] && return 0

  # Only scriptable / config text files
  [[ ! "$file" =~ \.(sh|bash|ps1|py|yml|yaml|json|toml|md)$ ]] && return 0
  [[ "$file" =~ $IRON_DOME_BINARY_SKIP ]] && return 0
  # Skip iron-dome's own files (legitimate hardcoded paths in installer)
  [[ "$file" =~ iron-dome.*\.(sh|py|yml)$ ]] && return 0
  [[ "$file" =~ src/guards/.*\.sh$ ]] && return 0

  local patterns=(
    '[A-Z]:\\\\(Users|EW|Program)'
    '/c/EW/'
    '/opt/easyway/'
    '/home/[a-z]+/'
    'C:/Users/'
  )

  local found=0
  local matches
  for p in "${patterns[@]}"; do
    matches=$(git diff --cached -- "$file" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E "$p" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      found=$((found + 1))
    fi
  done

  if [[ $found -eq 0 ]]; then return 0; fi

  local severity="advisory"
  if [[ "${ANTI_HARDCODED_BLOCKING:-}" == "1" ]]; then
    severity="blocking"
    _report_finding "ANTI_HARDCODED" "Hardcoded path/value" "$file" "1"
    IRON_DOME_OTHER_FOUND=$((IRON_DOME_OTHER_FOUND + 1))
    _guard_log "anti_hardcoded" "blocking" "$file: $found hardcoded patterns"
    return 1
  fi

  echo "  Anti-Hardcoded Audit: $file has $found possible hardcoded path(s) (advisory)"
  IRON_DOME_ADVISORY_FOUND=$((IRON_DOME_ADVISORY_FOUND + 1))
  _guard_log "anti_hardcoded" "advisory" "$file: $found hardcoded patterns"
  return 0
}
