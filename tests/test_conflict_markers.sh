#!/usr/bin/env bash
# Iron Dome Tests — Conflict Markers Guard

suite "Conflict Markers Guard"

# --- Detects <<<<<<< marker ---
setup_sandbox
reload_core
printf '<<<<<<< HEAD\nmy changes\n=======\ntheir changes\n>>>>>>> branch\n' > conflict.txt
guard_conflict_markers "conflict.txt" > "$TMPDIR_TEST/guard_out.txt" 2>&1 || true
output=$(cat "$TMPDIR_TEST/guard_out.txt")
assert_contains "detects <<<<<<< marker" "CONFLICT_MARKER" "$output"
assert_eq "finds 3 markers (<<<, ===, >>>)" "3" "$IRON_DOME_CONFLICTS_FOUND"
teardown_sandbox

# --- Clean file (no markers) ---
setup_sandbox
reload_core
echo 'normal code here' > clean.txt
output=$(guard_conflict_markers "clean.txt" 2>&1 || true)
assert_eq "clean file has zero conflicts" "0" "$IRON_DOME_CONFLICTS_FOUND"
teardown_sandbox

# --- Does not false-positive on short sequences ---
setup_sandbox
reload_core
echo '<<< not a conflict' > short.txt
output=$(guard_conflict_markers "short.txt" 2>&1 || true)
assert_eq "ignores short < sequence" "0" "$IRON_DOME_CONFLICTS_FOUND"
teardown_sandbox
