#!/usr/bin/env bash
# ============================================================================
# Iron Dome Guard: Local Links (G-CI-3)
# ============================================================================
# Blocks commits of package-lock.json containing local symlink references.
# These work on the developer's machine but break in CI.
#
# Trigger: staged package-lock.json
# Severity: BLOCKING
# ============================================================================

guard_local_links() {
  local file="$1"

  # Only check package-lock.json
  [[ "$(basename "$file")" != "package-lock.json" ]] && return 0

  # Whitelist check
  if type _is_whitelisted &>/dev/null && _is_whitelisted "local_links" "$file"; then
    return 0
  fi

  local found=0

  # Check for relative path resolved links (npm link artifacts)
  local matches
  matches=$(grep -nP '"resolved":\s*"(\.\.|file:)' "$file" 2>/dev/null || true)

  if [[ -n "$matches" ]]; then
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      local line_num="${match_line%%:*}"
      _report_finding "LOCAL_LINK" "local symlink in package-lock.json" "$file" "$line_num"
      found=$((found + 1))
    done <<< "$matches"
  fi

  if [[ $found -gt 0 ]]; then
    echo "  FIX: npm uninstall <pkg> && npm install <pkg> (removes local link)"
    echo "  CHECK: grep '\"resolved\": \"\\.\\.' package-lock.json"
    return 1
  fi

  return 0
}
