#!/usr/bin/env bash
# Iron Dome CI — ShellCheck Lint
# Runs shellcheck on shell scripts. Requires shellcheck installed.
#
# Usage: shellcheck-lint.sh [file...]
#   No args → finds all *.sh files (excludes node_modules, .git, vendor)
#
# Exit: 0 = clean, 1 = warnings/errors found
# PBI #517 — S184

set -euo pipefail

if ! command -v shellcheck &>/dev/null; then
  echo "Iron Dome CI: shellcheck not found. Install: apt install shellcheck"
  echo "Skipping (non-blocking)."
  exit 0
fi

files=("$@")

if [[ ${#files[@]} -eq 0 ]]; then
  mapfile -t files < <(find . -name '*.sh' -type f \
    -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -path '*/vendor/*' -not -path '*/.venv/*' 2>/dev/null)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "Iron Dome CI: no shell scripts found. Skipping."
  exit 0
fi

errors=0
echo "Iron Dome CI: ShellCheck Lint (${#files[@]} file(s))"

for f in "${files[@]}"; do
  if shellcheck -S warning "$f" 2>/dev/null; then
    : # silent on success
  else
    echo "  WARN  $f"
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  echo "ShellCheck: $errors file(s) with warnings."
  echo "Run 'shellcheck <file>' for details."
  exit 1
fi

echo "ShellCheck: all ${#files[@]} scripts clean."
exit 0
