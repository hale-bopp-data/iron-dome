# ============================================================================
# Tests: check-inline-credentials.sh
# ============================================================================
# Sourced by run-tests.sh — uses suite/assert_* framework from there.

CHECK_SCRIPT="$PROJECT_ROOT/src/checks/check-inline-credentials.sh"

suite "Inline Credentials Check"

# --- Test 1: Clean repo (no credentials) ---
setup_sandbox
git remote add origin "https://dev.azure.com/EasyWayData/Project/_git/repo"
output=$(bash "$CHECK_SCRIPT" "$TMPDIR_TEST" 2>&1 || true)
exit_code=0
bash "$CHECK_SCRIPT" "$TMPDIR_TEST" >/dev/null 2>&1 || exit_code=$?
assert_eq "clean repo exits 0" "0" "$exit_code"
assert_contains "clean repo reports 0 tainted" "Tainted:        0" "$output"
teardown_sandbox

# --- Test 2: Tainted repo (inline credential in remote URL) ---
setup_sandbox
# Write a tainted .git/config using git config to avoid
# URL-format fake credentials in source that trigger Gate 3 mirror scanner (PBI #2286)
git -C "$TMPDIR_TEST" config remote.mirror.url "https://user:$(printf 's3cretP4ss')@github.com/org/repo.git"
git -C "$TMPDIR_TEST" config remote.mirror.fetch "+refs/heads/*:refs/remotes/mirror/*"
output=$(bash "$CHECK_SCRIPT" "$TMPDIR_TEST" 2>&1 || true)
exit_code=0
bash "$CHECK_SCRIPT" "$TMPDIR_TEST" >/dev/null 2>&1 || exit_code=$?
assert_eq "tainted repo exits 1" "1" "$exit_code"
assert_contains "tainted repo reports finding" "FOUND:" "$output"
assert_contains "tainted repo reports 1 tainted" "Tainted:        1" "$output"
# Verify credential is redacted in output
assert_not_contains "credential not leaked in output" "s3cretP4ss" "$output"
teardown_sandbox

# --- Test 3: SSH URL is safe (not flagged) ---
setup_sandbox
git remote add origin "git@dev.azure.com:v3/EasyWayData/Project/repo"
output=$(bash "$CHECK_SCRIPT" "$TMPDIR_TEST" 2>&1 || true)
exit_code=0
bash "$CHECK_SCRIPT" "$TMPDIR_TEST" >/dev/null 2>&1 || exit_code=$?
assert_eq "SSH remote exits 0" "0" "$exit_code"
teardown_sandbox

# --- Test 4: Mixed repos (one clean, one tainted) ---
setup_sandbox
CLEAN_REPO="$TMPDIR_TEST"

TAINTED_REPO=$(mktemp -d)
cd "$TAINTED_REPO"
git init -q
git config user.email "test@iron-dome.dev"
git config user.name "Iron Dome Tests"
echo "init" > .gitkeep && git add .gitkeep && git commit -q -m "init"
git -C "$TAINTED_REPO" config remote.origin.url "https://pat:$(printf 'aaabbbccc')@dev.azure.com/Org/Proj/_git/repo"
cd "$TMPDIR_TEST"

exit_code=0
bash "$CHECK_SCRIPT" "$CLEAN_REPO" "$TAINTED_REPO" >/dev/null 2>&1 || exit_code=$?
assert_eq "mixed repos exits 1 (at least one tainted)" "1" "$exit_code"

output=$(bash "$CHECK_SCRIPT" "$CLEAN_REPO" "$TAINTED_REPO" 2>&1 || true)
assert_contains "mixed repos scanned 2" "Repos scanned:  2" "$output"
assert_contains "mixed repos 1 tainted" "Tainted:        1" "$output"

rm -rf "$TAINTED_REPO"
teardown_sandbox

# --- Test 5: No repos provided exits 2 ---
exit_code=0
bash "$CHECK_SCRIPT" >/dev/null 2>&1 || exit_code=$?
assert_eq "no repos exits 2" "2" "$exit_code"

# --- Test 6: Non-existent path (skipped, not crash) ---
setup_sandbox
exit_code=0
bash "$CHECK_SCRIPT" "/nonexistent/path" >/dev/null 2>&1 || exit_code=$?
assert_eq "nonexistent repo path exits 0 (skipped)" "0" "$exit_code"
teardown_sandbox

# --- Test 7: HTTPS URL without credentials is safe ---
setup_sandbox
git remote add origin "https://dev.azure.com/EasyWayData/Project/_git/repo"
git remote add backup "https://github.com/org/repo.git"
exit_code=0
bash "$CHECK_SCRIPT" "$TMPDIR_TEST" >/dev/null 2>&1 || exit_code=$?
assert_eq "HTTPS without creds exits 0" "0" "$exit_code"
teardown_sandbox

# --- Test 8: Telemetry file written ---
setup_sandbox
TELEM_FILE=$(mktemp)
git -C "$TMPDIR_TEST" config remote.leak.url "https://admin:$(printf 'hunter2')@gitlab.com/org/repo.git"
bash "$CHECK_SCRIPT" --telemetry-file "$TELEM_FILE" "$TMPDIR_TEST" >/dev/null 2>&1 || true
telem_content=$(cat "$TELEM_FILE" 2>/dev/null || echo "")
assert_contains "telemetry written" "inline_credentials" "$telem_content"
assert_contains "telemetry has severity blocking" "blocking" "$telem_content"
rm -f "$TELEM_FILE"
teardown_sandbox
