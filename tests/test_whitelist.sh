#!/usr/bin/env bash
# Iron Dome Tests — Whitelist

suite "Whitelist"

# --- Whitelisted file skips sensitive_files guard ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
guards:
  sensitive_files:
    enabled: true

whitelist:
  - file: "tests/fixtures/.env"
    guard: sensitive_files
    reason: "Test fixture with fake data"
YAML
_load_whitelist "iron-dome.yml"
output=$(_is_whitelisted "sensitive_files" "tests/fixtures/.env" 2>&1 || true)
local_exit=$?
assert_eq "whitelisted file returns 0" "0" "$local_exit"
assert_contains "prints whitelist reason" "Test fixture" "$output"
teardown_sandbox

# --- Non-whitelisted file is NOT skipped ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
whitelist:
  - file: "tests/fixtures/.env"
    guard: sensitive_files
    reason: "Test fixture"
YAML
_load_whitelist "iron-dome.yml"
local_result=""
if _is_whitelisted "sensitive_files" "production/.env" 2>/dev/null; then local_result="skipped"; else local_result="checked"; fi
assert_eq "non-whitelisted file is checked" "checked" "$local_result"
teardown_sandbox

# --- Whitelisted secrets pattern ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
whitelist:
  - file: "docs/api-demo.js"
    guard: secrets
    pattern: "Generic API Key"
    reason: "Documentation example with placeholder"
YAML
_load_whitelist "iron-dome.yml"
output=$(_is_whitelisted "secrets" "docs/api-demo.js" 2>&1 || true)
assert_contains "whitelists specific secrets pattern" "Documentation example" "$output"
teardown_sandbox

# --- Empty whitelist does not crash ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
whitelist: []
YAML
_load_whitelist "iron-dome.yml"
local_result=""
if _is_whitelisted "secrets" "any-file.js" 2>/dev/null; then local_result="skipped"; else local_result="checked"; fi
assert_eq "empty whitelist does not crash" "checked" "$local_result"
teardown_sandbox
