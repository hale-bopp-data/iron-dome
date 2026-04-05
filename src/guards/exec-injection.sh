#!/usr/bin/env bash
# Iron Dome Guard: Command Injection via execSync
# Hook: pre-commit
# Default: ON for JS/TS projects
#
# Detects execSync / spawnSync with string interpolation (template literals
# or concatenation) — the #1 command injection vector in Node.js.
# Safe alternative: execFileSync("cmd", [args]) with array syntax.

guard_exec_injection() {
  local file="$1"

  # Only scan JS/TS files
  case "$file" in
    *.js|*.mjs|*.cjs|*.ts|*.mts) ;;
    *) return 0 ;;
  esac

  if _is_whitelisted "exec_injection" "$file"; then return 0; fi

  local found=0

  # Pattern 1: execSync with template literal containing ${
  local p1='execSync\s*\(\s*`[^`]*\$\{'
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p1" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "INJECTION" "execSync with template interpolation" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 2: execSync with string concatenation (+)
  local p2='execSync\s*\(\s*["\x27][^)]*\+\s*[a-zA-Z]'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p2" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "INJECTION" "execSync with string concatenation" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 3: spawnSync with shell:true + string arg
  local p3='spawnSync\s*\([^)]*shell\s*:\s*true'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p3" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "INJECTION" "spawnSync with shell:true" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
