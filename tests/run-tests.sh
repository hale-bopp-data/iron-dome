#!/usr/bin/env bash
# ============================================================================
# Iron Dome — Test Runner
# ============================================================================
# Self-contained test runner. No external dependencies (no bats, no shunit2).
# Usage: bash tests/run-tests.sh
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Colors (if terminal supports them) ---
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' BOLD='' NC=''
fi

# --- Counters ---
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_SUITE=""

# --- Test framework ---
suite() {
  CURRENT_SUITE="$1"
  echo ""
  echo -e "${BOLD}━━━ $1 ━━━${NC}"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}✓${NC} $desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    expected: ${YELLOW}${expected}${NC}"
    echo -e "    actual:   ${YELLOW}${actual}${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    expected to contain: ${YELLOW}${needle}${NC}"
    echo -e "    in: ${YELLOW}${haystack:0:200}${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if ! echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    expected NOT to contain: ${YELLOW}${needle}${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_exit_code() {
  local desc="$1" expected="$2"
  shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  assert_eq "$desc" "$expected" "$actual"
}

# --- Setup temp dir with git repo ---
TMPDIR_TEST=""
setup_sandbox() {
  TMPDIR_TEST=$(mktemp -d)
  cd "$TMPDIR_TEST"
  git init -q
  git config user.email "test@iron-dome.dev"
  git config user.name "Iron Dome Tests"
  # Initial commit so git works properly
  echo "init" > .gitkeep
  git add .gitkeep
  git commit -q -m "init"
  # Export so core.sh can find it
  export IRON_DOME_HOME="$PROJECT_ROOT"
}

teardown_sandbox() {
  cd "$PROJECT_ROOT"
  if [[ -n "$TMPDIR_TEST" ]] && [[ -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# --- Source core (resets state) ---
reload_core() {
  # Reset global state
  IRON_DOME_FINDINGS=()
  IRON_DOME_SECRETS_FOUND=0
  IRON_DOME_CONFLICTS_FOUND=0
  IRON_DOME_DOCKER_FOUND=0
  IRON_DOME_OTHER_FOUND=0
  IRON_DOME_ADVISORY_FOUND=0
  IRON_DOME_SAFE_REGEX=""
  IRON_DOME_DISABLED_PATTERNS=()

  # Re-declare associative arrays
  unset IRON_DOME_GUARD_ENABLED 2>/dev/null || true
  unset IRON_DOME_WHITELIST 2>/dev/null || true
  declare -gA IRON_DOME_GUARD_ENABLED
  declare -gA IRON_DOME_WHITELIST

  source "$PROJECT_ROOT/src/iron-dome-core.sh"

  # Load all guard modules
  for _guard_file in "$PROJECT_ROOT"/src/guards/*.sh; do
    [[ -f "$_guard_file" ]] && source "$_guard_file"
  done
}

# ============================================================================
# TEST SUITES
# ============================================================================

# --- Run all test files ---
echo ""
echo -e "${BOLD}Iron Dome v2.0.0 — Test Suite${NC}"
echo "============================================"

for test_file in "$SCRIPT_DIR"/test_*.sh; do
  [[ -f "$test_file" ]] || continue
  source "$test_file"
done

# --- Summary ---
echo ""
echo "============================================"
if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}ALL PASSED${NC}: ${TESTS_PASSED}/${TESTS_RUN} tests"
  exit 0
else
  echo -e "${RED}${BOLD}FAILED${NC}: ${TESTS_FAILED}/${TESTS_RUN} tests failed"
  exit 1
fi
