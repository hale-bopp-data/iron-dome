#!/usr/bin/env bash
# Iron Dome Guard: XSS via innerHTML
# Hook: pre-commit
# Default: ON for JS/TS projects
#
# Detects innerHTML assignments with dynamic content (template literals,
# variables, function calls). SVG injection is especially dangerous.
# Safe alternative: textContent, DOM API (createElement/appendChild), DOMPurify.

guard_innerhtml_xss() {
  local file="$1"

  # Only scan JS/TS/HTML files
  case "$file" in
    *.js|*.mjs|*.ts|*.mts|*.tsx|*.jsx|*.html) ;;
    *) return 0 ;;
  esac

  if _is_whitelisted "innerhtml_xss" "$file"; then return 0; fi

  local found=0

  # Pattern 1: .innerHTML = `...${  (template literal with interpolation)
  local p1='\.innerHTML\s*=\s*`[^`]*\$\{'
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p1" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "XSS" "innerHTML with template interpolation" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 2: .innerHTML = variable (not a static string)
  local p2='\.innerHTML\s*=\s*[a-zA-Z_][a-zA-Z0-9_.]*[^;]*;'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p2" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    # Skip static strings: innerHTML = "<div>static</div>"
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '\.innerHTML\s*=\s*["\x27]' 2>/dev/null; then
      continue
    fi
    # Skip empty: innerHTML = ""
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '\.innerHTML\s*=\s*["\x27]["\x27]' 2>/dev/null; then
      continue
    fi
    local line_num="${match_line%%:*}"
    _report_finding "XSS" "innerHTML assigned from variable" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 3: .innerHTML = result.svg or .innerHTML = data.html (SVG/HTML injection)
  local p3='\.innerHTML\s*=\s*[a-zA-Z_]+\.(svg|html|markup|template|content)\b'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p3" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "XSS" "innerHTML from .svg/.html property (high risk)" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
