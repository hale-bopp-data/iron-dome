#!/usr/bin/env bash
# Iron Dome CI — Compose Validate
# Validates docker-compose files via `docker compose config`.
# Catches YAML errors, invalid service refs, missing env vars.
#
# Usage: compose-validate.sh [file...]
#   No args → finds all docker-compose*.yml and compose*.yml
#
# Exit: 0 = all valid, 1 = errors found
# PBI #517 — S184

set -euo pipefail

files=("$@")

if [[ ${#files[@]} -eq 0 ]]; then
  mapfile -t files < <(find . -maxdepth 3 \
    \( -name 'docker-compose*.yml' -o -name 'compose*.yml' \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "Iron Dome CI: no compose files found. Skipping."
  exit 0
fi

errors=0
echo "Iron Dome CI: Compose Validate (${#files[@]} file(s))"

for f in "${files[@]}"; do
  if docker compose -f "$f" config --quiet 2>/dev/null; then
    echo "  OK    $f"
  else
    echo "  FAIL  $f"
    docker compose -f "$f" config 2>&1 | head -5 | sed 's/^/        /'
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  echo "BLOCKED: $errors compose file(s) invalid."
  exit 1
fi

echo "All compose files valid."
exit 0
