#!/usr/bin/env bash
# Iron Dome Tests — Sensitive Files Guard

suite "Sensitive Files Guard"

# --- Blocks .env ---
setup_sandbox
reload_core
echo 'SECRET=foo' > .env
output=$(guard_sensitive_files ".env" 2>&1 || true)
assert_contains "blocks .env file" "SENSITIVE_FILE" "$output"
teardown_sandbox

# --- Blocks .pem files ---
setup_sandbox
reload_core
echo 'cert' > server.pem
output=$(guard_sensitive_files "server.pem" 2>&1 || true)
assert_contains "blocks .pem file" "SENSITIVE_FILE" "$output"
teardown_sandbox

# --- Blocks id_rsa ---
setup_sandbox
reload_core
echo 'key' > id_rsa
output=$(guard_sensitive_files "id_rsa" 2>&1 || true)
assert_contains "blocks id_rsa" "SENSITIVE_FILE" "$output"
teardown_sandbox

# --- Blocks id_ed25519 ---
setup_sandbox
reload_core
echo 'key' > id_ed25519
output=$(guard_sensitive_files "id_ed25519" 2>&1 || true)
assert_contains "blocks id_ed25519" "SENSITIVE_FILE" "$output"
teardown_sandbox

# --- Allows .env.example ---
setup_sandbox
reload_core
echo 'PLACEHOLDER=xxx' > .env.example
output=$(guard_sensitive_files ".env.example" 2>&1 || true)
assert_not_contains "allows .env.example" "SENSITIVE_FILE" "$output"
teardown_sandbox

# --- Allows .env.template ---
setup_sandbox
reload_core
echo 'PLACEHOLDER=xxx' > .env.template
output=$(guard_sensitive_files ".env.template" 2>&1 || true)
assert_not_contains "allows .env.template" "SENSITIVE_FILE" "$output"
teardown_sandbox

# --- Allows normal files ---
setup_sandbox
reload_core
echo 'code' > app.js
output=$(guard_sensitive_files "app.js" 2>&1 || true)
assert_not_contains "allows normal files" "SENSITIVE_FILE" "$output"
teardown_sandbox
