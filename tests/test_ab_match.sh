#!/usr/bin/env bash
# Iron Dome Tests — AB# Branch Match Guard
#
# Guard state (IRON_DOME_ADVISORY_FOUND) is a parent-shell variable, so the
# guard must be called WITHOUT a subshell (no $(...)), otherwise the
# increment is lost. Tests below capture the advisory text via a temp file
# to sidestep that issue.

suite "AB#/Branch Match Guard"

_msg_file_for() {
  local msg="$1"
  local f
  f=$(mktemp)
  printf '%s\n' "$msg" > "$f"
  echo "$f"
}

# --- Mismatch -> advisory ---
setup_sandbox
reload_core
git checkout -q -B "feat/1242-other" 2>/dev/null
f=$(_msg_file_for "feat: something AB#1243")
err_file=$(mktemp)
guard_ab_match "$f" 2>"$err_file"
err_out=$(cat "$err_file")
rm -f "$f" "$err_file"
assert_eq "mismatch triggers advisory" "1" "$IRON_DOME_ADVISORY_FOUND"
assert_contains "mismatch message mentions AB-MISMATCH" "AB-MISMATCH" "$err_out"
teardown_sandbox

# --- Match -> silent ---
setup_sandbox
reload_core
git checkout -q -B "feat/1305-ab-match" 2>/dev/null
f=$(_msg_file_for "feat: wire thing AB#1305")
guard_ab_match "$f" 2>/dev/null
rm -f "$f"
assert_eq "matching AB# stays silent" "0" "$IRON_DOME_ADVISORY_FOUND"
teardown_sandbox

# --- Multi-AB#, at least one matches -> silent ---
setup_sandbox
reload_core
git checkout -q -B "fix/1305-foo" 2>/dev/null
f=$(_msg_file_for "fix: AB#1305 depends on AB#1243")
guard_ab_match "$f" 2>/dev/null
rm -f "$f"
assert_eq "multi-AB with one match is silent" "0" "$IRON_DOME_ADVISORY_FOUND"
teardown_sandbox

# --- Multi-AB#, none matches -> advisory ---
setup_sandbox
reload_core
git checkout -q -B "fix/1242-other" 2>/dev/null
f=$(_msg_file_for "fix: AB#1243 AB#1244 follow-up")
guard_ab_match "$f" 2>/dev/null
rm -f "$f"
assert_eq "multi-AB none matches -> advisory" "1" "$IRON_DOME_ADVISORY_FOUND"
teardown_sandbox

# --- No AB#N in message -> silent ---
setup_sandbox
reload_core
git checkout -q -B "feat/1305-ab-match" 2>/dev/null
f=$(_msg_file_for "chore: bump versions")
guard_ab_match "$f" 2>/dev/null
rm -f "$f"
assert_eq "no AB# -> silent" "0" "$IRON_DOME_ADVISORY_FOUND"
teardown_sandbox

# --- Protected branch (main) -> silent ---
setup_sandbox
reload_core
git checkout -q -B "main" 2>/dev/null
f=$(_msg_file_for "feat: AB#1243 hotfix")
guard_ab_match "$f" 2>/dev/null
rm -f "$f"
assert_eq "main branch is skipped" "0" "$IRON_DOME_ADVISORY_FOUND"
teardown_sandbox

# --- Protected branch (develop) -> silent ---
setup_sandbox
reload_core
git checkout -q -B "develop" 2>/dev/null
f=$(_msg_file_for "feat: AB#1243 hotfix")
guard_ab_match "$f" 2>/dev/null
rm -f "$f"
assert_eq "develop branch is skipped" "0" "$IRON_DOME_ADVISORY_FOUND"
teardown_sandbox

# --- Non-PBI branch format -> silent ---
setup_sandbox
reload_core
git checkout -q -B "personal/evgenia-notes" 2>/dev/null
f=$(_msg_file_for "chore: AB#1243 cleanup")
guard_ab_match "$f" 2>/dev/null
rm -f "$f"
assert_eq "non-PBI branch format is skipped" "0" "$IRON_DOME_ADVISORY_FOUND"
teardown_sandbox

# --- Guard never blocks (returns 0 even on mismatch) ---
setup_sandbox
reload_core
git checkout -q -B "feat/1242-other" 2>/dev/null
f=$(_msg_file_for "feat: AB#1999 cross-reference")
guard_ab_match "$f" 2>/dev/null
rc=$?
rm -f "$f"
assert_eq "guard returns 0 even on mismatch" "0" "$rc"
teardown_sandbox
