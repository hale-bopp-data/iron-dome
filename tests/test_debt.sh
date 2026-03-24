#!/usr/bin/env bash
# Iron Dome Tests — Debt Guard

suite "Debt Guard"

# --- Detects TODO ---
setup_sandbox
reload_core
echo '// TODO: fix this later' > app.js
output=$(guard_debt "app.js" 2>&1 || true)
assert_contains "detects TODO marker" "DEBT" "$output"
teardown_sandbox

# --- Detects FIXME ---
setup_sandbox
reload_core
echo '# FIXME: broken edge case' > app.py
output=$(guard_debt "app.py" 2>&1 || true)
assert_contains "detects FIXME marker" "DEBT" "$output"
teardown_sandbox

# --- Detects HACK ---
setup_sandbox
reload_core
echo '// HACK: temporary workaround' > app.js
output=$(guard_debt "app.js" 2>&1 || true)
assert_contains "detects HACK marker" "DEBT" "$output"
teardown_sandbox

# --- Skips markdown files ---
setup_sandbox
reload_core
echo '# TODO: write docs' > notes.md
output=$(guard_debt "notes.md" 2>&1 || true)
assert_eq "skips .md files" "0" "$IRON_DOME_ADVISORY_FOUND"
teardown_sandbox

# --- Clean code (no debt) ---
setup_sandbox
reload_core
echo 'function hello() { return "world"; }' > clean.js
output=$(guard_debt "clean.js" 2>&1 || true)
assert_eq "clean file has zero debt" "0" "$IRON_DOME_ADVISORY_FOUND"
teardown_sandbox
