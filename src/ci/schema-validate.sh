#!/usr/bin/env bash
# Iron Dome CI — Schema Validate
# Validates iron-dome.yml + examples/*.yml against schema/iron-dome.schema.json,
# and .iron-dome.yml against schema/iron-dome.override.schema.json.
#
# Validator auto-select (zero hard dependency):
#   1. check-jsonschema (pipx/pip)         — preferred
#   2. python3 + jsonschema + PyYAML       — fallback
#   3. none available                      — SKIP (advisory, never a false fail)
#
# Exit: 0 = all valid OR skipped; 1 = at least one file invalid.
# PBI #427 — S157.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMA="$ROOT/schema/iron-dome.schema.json"
OVERRIDE_SCHEMA="$ROOT/schema/iron-dome.override.schema.json"

if [[ ! -f "$SCHEMA" ]]; then
  echo "Iron Dome CI: schema not found ($SCHEMA). Skipping."
  exit 0
fi

# Build "file|schema" pairs
pairs=()
[[ -f "$ROOT/iron-dome.yml" ]] && pairs+=("$ROOT/iron-dome.yml|$SCHEMA")
if compgen -G "$ROOT/examples/*.yml" >/dev/null 2>&1; then
  for f in "$ROOT"/examples/*.yml; do pairs+=("$f|$SCHEMA"); done
fi
[[ -f "$ROOT/.iron-dome.yml" ]] && [[ -f "$OVERRIDE_SCHEMA" ]] && pairs+=("$ROOT/.iron-dome.yml|$OVERRIDE_SCHEMA")

if [[ ${#pairs[@]} -eq 0 ]]; then
  echo "Iron Dome CI: no config files to validate. Skipping."
  exit 0
fi

# Select validator
mode=""
if command -v check-jsonschema >/dev/null 2>&1; then
  mode="check-jsonschema"
elif python3 -c "import jsonschema, yaml" >/dev/null 2>&1; then
  mode="python"
else
  echo "Iron Dome CI: no JSON-Schema validator available"
  echo "  (install 'check-jsonschema' or 'pip install jsonschema pyyaml'). Skipping (advisory)."
  exit 0
fi

echo "Iron Dome CI: Schema Validate (${#pairs[@]} file(s), validator=$mode)"
errors=0

for pair in "${pairs[@]}"; do
  file="${pair%%|*}"
  schema="${pair##*|}"
  rel="${file#"$ROOT"/}"
  if [[ "$mode" == "check-jsonschema" ]]; then
    if check-jsonschema --schemafile "$schema" "$file" >/dev/null 2>&1; then
      echo "  OK    $rel"
    else
      echo "  FAIL  $rel"
      check-jsonschema --schemafile "$schema" "$file" 2>&1 | sed "s/^/        /" || true
      errors=$((errors + 1))
    fi
  else
    if python3 - "$schema" "$file" <<"PY" >/dev/null 2>&1
import sys, json, yaml, jsonschema
schema = json.load(open(sys.argv[1]))
data = yaml.safe_load(open(sys.argv[2]))
jsonschema.validate(data, schema)
PY
    then
      echo "  OK    $rel"
    else
      echo "  FAIL  $rel"
      python3 - "$schema" "$file" 2>&1 <<"PY" | tail -3 | sed "s/^/        /" || true
import sys, json, yaml, jsonschema
schema = json.load(open(sys.argv[1]))
data = yaml.safe_load(open(sys.argv[2]))
jsonschema.validate(data, schema)
PY
      errors=$((errors + 1))
    fi
  fi
done

if [[ $errors -gt 0 ]]; then
  echo "BLOCKED: $errors config file(s) failed schema validation."
  exit 1
fi

echo "Schema: all ${#pairs[@]} config file(s) valid."
exit 0
