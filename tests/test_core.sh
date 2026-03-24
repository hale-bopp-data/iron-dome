#!/usr/bin/env bash
# Iron Dome Tests — Core functions

suite "Core Functions"

# --- _should_skip_file: binary files ---
setup_sandbox
reload_core
local_result=""
if _should_skip_file "image.png"; then local_result="skipped"; else local_result="scanned"; fi
assert_eq "skips .png files" "skipped" "$local_result"
if _should_skip_file "font.woff2"; then local_result="skipped"; else local_result="scanned"; fi
assert_eq "skips .woff2 files" "skipped" "$local_result"
if _should_skip_file "app.js"; then local_result="skipped"; else local_result="scanned"; fi
assert_eq "scans .js files" "scanned" "$local_result"
teardown_sandbox

# --- _should_skip_file: skip patterns ---
setup_sandbox
reload_core
local_result=""
if _should_skip_file "node_modules/foo/bar.js"; then local_result="skipped"; else local_result="scanned"; fi
assert_eq "skips node_modules/" "skipped" "$local_result"
if _should_skip_file ".git/objects/abc"; then local_result="skipped"; else local_result="scanned"; fi
assert_eq "skips .git/" "skipped" "$local_result"
if _should_skip_file "vendor/lib.go"; then local_result="skipped"; else local_result="scanned"; fi
assert_eq "skips vendor/" "skipped" "$local_result"
teardown_sandbox

# --- _is_safe_match: env var references ---
setup_sandbox
reload_core
local_result=""
if _is_safe_match 'password = ${DB_PASSWORD}'; then local_result="safe"; else local_result="unsafe"; fi
assert_eq 'safe: ${ENV_VAR} pattern' "safe" "$local_result"
if _is_safe_match 'key = process.env.API_KEY'; then local_result="safe"; else local_result="unsafe"; fi
assert_eq "safe: process.env pattern" "safe" "$local_result"
if _is_safe_match 'secret = os.environ["KEY"]'; then local_result="safe"; else local_result="unsafe"; fi
assert_eq "safe: os.environ pattern" "safe" "$local_result"
teardown_sandbox

# --- _is_safe_match: real secrets are NOT safe ---
setup_sandbox
reload_core
local_result=""
if _is_safe_match 'password = "RealSecretValue123"'; then local_result="safe"; else local_result="unsafe"; fi
assert_eq "unsafe: real hardcoded password" "unsafe" "$local_result"
teardown_sandbox

# --- _is_pattern_disabled ---
setup_sandbox
reload_core
IRON_DOME_DISABLED_PATTERNS=("GitHub PAT" "Bearer Token")
local_result=""
if _is_pattern_disabled "GitHub PAT"; then local_result="disabled"; else local_result="enabled"; fi
assert_eq "disabled pattern detected" "disabled" "$local_result"
if _is_pattern_disabled "Private Key"; then local_result="disabled"; else local_result="enabled"; fi
assert_eq "non-disabled pattern is enabled" "enabled" "$local_result"
teardown_sandbox

# --- _report_finding: increments correct counter ---
setup_sandbox
reload_core
_report_finding "SECRET" "test" "file.js" "1" >/dev/null
assert_eq "SECRET increments secrets counter" "1" "$IRON_DOME_SECRETS_FOUND"
_report_finding "CONFLICT_MARKER" "test" "file.js" "2" >/dev/null
assert_eq "CONFLICT increments conflicts counter" "1" "$IRON_DOME_CONFLICTS_FOUND"
_report_finding "DOCKER_RUN" "test" "file.sh" "3" >/dev/null
assert_eq "DOCKER increments docker counter" "1" "$IRON_DOME_DOCKER_FOUND"
_report_finding "DEBT" "test" "file.js" "4" >/dev/null
assert_eq "DEBT increments advisory counter" "1" "$IRON_DOME_ADVISORY_FOUND"
assert_eq "total findings count" "4" "${#IRON_DOME_FINDINGS[@]}"
teardown_sandbox

# --- Version ---
setup_sandbox
reload_core
assert_eq "version is 2.1.0" "2.1.0" "$IRON_DOME_VERSION"
teardown_sandbox
