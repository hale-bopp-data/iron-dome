#!/usr/bin/env bash
# Iron Dome Tests — Schema conformance (bridges PBI #427 schema <-> config files)
# PBI #427/#428.

suite "Schema Validation"

# --- schema files are valid JSON ---
setup_sandbox
reload_core
assert_exit_code "iron-dome.schema.json is valid JSON" 0 \
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PROJECT_ROOT/schema/iron-dome.schema.json"
assert_exit_code "iron-dome.override.schema.json is valid JSON" 0 \
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PROJECT_ROOT/schema/iron-dome.override.schema.json"
teardown_sandbox

# --- config files conform to the schema (graceful skip if no validator) ---
setup_sandbox
reload_core
if command -v check-jsonschema >/dev/null 2>&1 || python3 -c "import jsonschema, yaml" >/dev/null 2>&1; then
  assert_exit_code "iron-dome.yml + examples pass schema validation" 0 \
    bash "$PROJECT_ROOT/src/ci/schema-validate.sh"
else
  echo "  (skip) no JSON-Schema validator (check-jsonschema or python3 jsonschema+pyyaml) — schema-validate.sh not exercised"
fi
teardown_sandbox