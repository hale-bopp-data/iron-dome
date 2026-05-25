#!/usr/bin/env bash
# Iron Dome Tests — Edge Cases (empty, binary, large, encoding)
# PBI #428.

suite "Edge Cases"

# --- empty file: no findings, no crash ---
setup_sandbox
reload_core
: > empty.txt
guard_secrets "empty.txt" >/dev/null 2>&1 || true
assert_eq "empty file yields zero findings" "0" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox

# --- binary extension is skipped by the scanner ---
setup_sandbox
reload_core
assert_exit_code "binary .png is skipped" 0 _should_skip_file "image.png"
teardown_sandbox

# --- source file is NOT skipped ---
setup_sandbox
reload_core
assert_exit_code "source .js is not skipped" 1 _should_skip_file "app.js"
teardown_sandbox

# --- large file (>512KB) skipped by scan limit ---
setup_sandbox
reload_core
head -c 600000 /dev/zero | tr '\0' 'a' > big.txt
assert_exit_code "large file (>512KB) skipped by scan limit" 0 _should_skip_file "big.txt"
teardown_sandbox

# --- encoding: UTF-8 BOM + non-ASCII, secret still detected ---
setup_sandbox
reload_core
GHP="gh""p_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"
printf '\xEF\xBB\xBF# caf\xC3\xA9 config\nkey = "%s"\n' "$GHP" > bom.txt
out=$(guard_secrets "bom.txt" 2>&1 || true)
assert_contains "secret detected in UTF-8/BOM file" "GitHub PAT" "$out"
teardown_sandbox