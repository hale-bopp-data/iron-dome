#!/usr/bin/env bash
# Iron Dome Tests — Large File Guard

suite "Large File Guard"

# --- Blocks file over threshold ---
setup_sandbox
reload_core
IRON_DOME_MAX_FILE_KB=1  # 1KB threshold for testing
dd if=/dev/zero of=big.bin bs=1024 count=2 2>/dev/null
output=$(guard_large_file "big.bin" 2>&1 || true)
assert_contains "blocks file over 1KB" "LARGE_FILE" "$output"
teardown_sandbox

# --- Allows file under threshold ---
setup_sandbox
reload_core
IRON_DOME_MAX_FILE_KB=1024
echo 'small' > small.txt
output=$(guard_large_file "small.txt" 2>&1 || true)
assert_not_contains "allows small file" "LARGE_FILE" "$output"
teardown_sandbox

# --- Respects exclude patterns ---
setup_sandbox
reload_core
IRON_DOME_MAX_FILE_KB=1
IRON_DOME_LARGE_FILE_EXCLUDE=("*.lock")
dd if=/dev/zero of=package.lock bs=1024 count=2 2>/dev/null
output=$(guard_large_file "package.lock" 2>&1 || true)
assert_not_contains "excludes *.lock files" "LARGE_FILE" "$output"
teardown_sandbox
