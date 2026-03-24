#!/usr/bin/env bash
# Iron Dome Tests — CLI

suite "CLI"

# --- iron-dome version ---
setup_sandbox
output=$("$PROJECT_ROOT/iron-dome" version 2>&1)
assert_contains "version command shows version" "Iron Dome v" "$output"
assert_contains "version command shows philosophy" "Dumb Guard" "$output"
teardown_sandbox

# --- iron-dome config ---
setup_sandbox
output=$("$PROJECT_ROOT/iron-dome" config 2>&1)
assert_contains "config command runs" "secrets" "$output"
teardown_sandbox

# --- iron-dome doctor ---
setup_sandbox
output=$("$PROJECT_ROOT/iron-dome" doctor 2>&1 || true)
assert_contains "doctor command runs" "Iron Dome" "$output"
teardown_sandbox

# --- iron-dome with no args shows help ---
setup_sandbox
output=$("$PROJECT_ROOT/iron-dome" 2>&1 || true)
assert_contains "no-args shows usage" "iron-dome" "$output"
teardown_sandbox
