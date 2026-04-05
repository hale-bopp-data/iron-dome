#!/usr/bin/env bash
# Iron Dome Guard: eval() / Function() / vm.runInNewContext Injection
# Hook: pre-commit
# Default: ON
#
# Detects eval(), new Function(), and vm.runInNewContext with dynamic input.
# These are the most dangerous JavaScript injection vectors — they execute
# arbitrary code from strings.
#
# GEDI Invisible Shield: the best security is the one nobody notices.

guard_eval_injection() {
  local file="$1"

  case "$file" in
    *.js|*.mjs|*.cjs|*.ts|*.mts|*.tsx|*.jsx) ;;
    *) return 0 ;;
  esac

  if _is_whitelisted "eval_injection" "$file"; then return 0; fi

  local found=0

  # Pattern 1: eval() with anything other than a static string
  local p1='\beval\s*\('
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p1" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    # Skip comments
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '^\s*(//|\*)' 2>/dev/null; then continue; fi
    # Skip eslint disable comments that mention eval
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP 'eslint-disable|no-eval' 2>/dev/null; then continue; fi
    local line_num="${match_line%%:*}"
    _report_finding "EVAL" "eval() usage (code injection risk)" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 2: new Function() with dynamic content
  local p2='new\s+Function\s*\('
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p2" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '^\s*(//|\*)' 2>/dev/null; then continue; fi
    local line_num="${match_line%%:*}"
    _report_finding "EVAL" "new Function() usage (code injection risk)" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 3: vm.runInNewContext / vm.runInThisContext
  local p3='vm\.(runInNewContext|runInThisContext|compileFunction)\s*\('
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p3" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '^\s*(//|\*)' 2>/dev/null; then continue; fi
    local line_num="${match_line%%:*}"
    _report_finding "EVAL" "vm.run*Context() usage (sandbox escape risk)" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
