#!/usr/bin/env bash
# Iron Dome Tests — Secrets Guard

suite "Secrets Guard"

# --- Detects private keys ---
setup_sandbox
reload_core
echo '-----BEGIN RSA PRIVATE KEY-----' > test-key.txt
guard_secrets "test-key.txt" > "$TMPDIR_TEST/guard_out.txt" 2>&1 || true
output=$(cat "$TMPDIR_TEST/guard_out.txt")
assert_contains "detects RSA private key" "SECRET" "$output"
assert_eq "increments secrets counter" "1" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox

# --- Detects GitHub PAT ---
setup_sandbox
reload_core
echo 'const token = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"' > app.js
output=$(guard_secrets "app.js" 2>&1 || true)
assert_contains "detects GitHub PAT" "GitHub PAT" "$output"
teardown_sandbox

# --- Detects AWS Access Key ---
setup_sandbox
reload_core
echo 'aws_key = "AKIAIOSFODNN7EXAMPLE"' > config.py
output=$(guard_secrets "config.py" 2>&1 || true)
assert_contains "detects AWS access key" "AWS Access Key" "$output"
teardown_sandbox

# --- Detects hardcoded password ---
setup_sandbox
reload_core
echo 'password = "SuperSecret123!"' > db.py
output=$(guard_secrets "db.py" 2>&1 || true)
assert_contains "detects hardcoded password" "Hardcoded Password" "$output"
teardown_sandbox

# --- Detects bearer token ---
setup_sandbox
reload_core
echo 'Authorization: bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test' > req.sh
output=$(guard_secrets "req.sh" 2>&1 || true)
assert_contains "detects bearer token" "Bearer Token" "$output"
teardown_sandbox

# --- Safe: env var reference (not a secret) ---
setup_sandbox
reload_core
echo 'password = ${DB_PASSWORD}' > safe.py
output=$(guard_secrets "safe.py" 2>&1 || true)
assert_eq "ignores env var reference" "0" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox

# --- Safe: process.env (Node.js) ---
setup_sandbox
reload_core
echo 'const secret = process.env.API_SECRET' > safe.js
output=$(guard_secrets "safe.js" 2>&1 || true)
assert_eq "ignores process.env reference" "0" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox

# --- Safe: placeholder value ---
setup_sandbox
reload_core
echo 'api_key = "your_api_key_here"' > example.py
output=$(guard_secrets "example.py" 2>&1 || true)
assert_eq "ignores placeholder api_key" "0" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox

# --- Safe: ChangeMe placeholder ---
setup_sandbox
reload_core
echo 'password = "ChangeMe"' > template.py
output=$(guard_secrets "template.py" 2>&1 || true)
assert_eq "ignores ChangeMe placeholder" "0" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox

# --- Clean file (no secrets) ---
setup_sandbox
reload_core
echo 'console.log("hello world")' > clean.js
output=$(guard_secrets "clean.js" 2>&1 || true)
assert_eq "clean file has zero findings" "0" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox
