#!/usr/bin/env bash
# Iron Dome CI — JSON Validate
# Syntax-checks JSON files. Uses python3 json.tool (zero deps).
#
# Usage: json-validate.sh [file...]
#   No args → finds all *.json files (excludes node_modules, .git, package-lock)
#
# Exit: 0 = all valid, 1 = errors found
# PBI #517 — S184

set -euo pipefail

files=("$@")

if [[ ${#files[@]} -eq 0 ]]; then
  mapfile -t files < <(find . -name '*.json' -type f \
    -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -name 'package-lock.json' -not -path '*/vendor/*' 2>/dev/null)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "Iron Dome CI: no JSON files found. Skipping."
  exit 0
fi

errors=0
echo "Iron Dome CI: JSON Validate (${#files[@]} file(s))"

for f in "${files[@]}"; do
  # SEC #2761: pass the filename via argv, never interpolate it into the
  # Python source. A repo-controlled name like `'); import os; ... #.json`
  # would otherwise break out of the string and run as code on the CI agent.
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    : # silent on success
  else
    echo "  FAIL  $f"
    # Show the error
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>&1 | tail -1 | sed 's/^/        /'
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  echo "BLOCKED: $errors JSON file(s) invalid."
  exit 1
fi

echo "JSON: all ${#files[@]} files valid."
exit 0
