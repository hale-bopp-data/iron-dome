#!/usr/bin/env bash
# Iron Dome Tests — SEC #2761: trust-boundary bypass closed + filename RCE closed
#
# Proves the attacker-facing bypasses are CLOSED by default (no opt-in):
#   - in-repo iron-dome.yml cannot disable a critical guard (secrets)
#   - in-repo .iron-dome.yml disabled_patterns cannot suppress a built-in pattern
#   - in-repo whitelist cannot exempt a critical guard, nor use a broad glob
#   - the old substring guard match no longer leaks across guards
#   - json-validate.sh does not execute code embedded in a filename
#
# Secret-like fixtures are assembled at runtime ("gh""p" split) so this source
# file carries no literal token for the pre-commit scanner to flag.

suite "SEC #2761 — trust boundary + filename RCE"

GHP="gh""p_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"   # -> ghp_<36> at runtime only

# --- in-repo config may NOT disable a critical guard (no opt-in) ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
guards:
  secrets:
    enabled: false
YAML
_load_config
assert_eq "in-repo config cannot disable secrets" "true" "${IRON_DOME_GUARD_ENABLED[secrets]}"
teardown_sandbox

# --- the disable attempt is logged loudly to stderr ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
guards:
  secrets:
    enabled: false
YAML
warn=$(_load_config 2>&1 1>/dev/null || true)
assert_contains "disable attempt warns on stderr" "SECURITY" "$warn"
teardown_sandbox

# --- a NON-critical guard can still be tuned by in-repo config ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
guards:
  docker_run:
    enabled: true
YAML
_load_config
assert_eq "non-critical guard still tunable in-repo" "true" "${IRON_DOME_GUARD_ENABLED[docker_run]}"
teardown_sandbox

# --- in-repo disabled_patterns is IGNORED without opt-in ---
setup_sandbox
reload_core
printf 'guards:\n  secrets:\n    enabled: true\n' > iron-dome.yml
printf 'disabled_patterns:\n  - "GitHub PAT"\n' > .iron-dome.yml
_load_config
echo "gh = $GHP" > app.js
guard_secrets "app.js" >/dev/null 2>&1 || true
assert_eq "in-repo disabled_patterns does NOT suppress GitHub PAT" "1" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox

# --- in-repo whitelist cannot exempt a critical guard (no opt-in) ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
whitelist:
  - file: "tests/fixtures/.env"
    guard: sensitive_files
    reason: "fixture"
YAML
_load_whitelist "iron-dome.yml"
res=""
if _is_whitelisted "sensitive_files" "tests/fixtures/.env" 2>/dev/null; then res="skipped"; else res="checked"; fi
assert_eq "in-repo whitelist cannot exempt critical guard" "checked" "$res"
teardown_sandbox

# --- broad glob whitelist is rejected even with opt-in ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
whitelist:
  - file: "*"
    guard: secrets
    reason: "whitelist everything"
YAML
_load_whitelist "iron-dome.yml"
res=""
if IRON_DOME_ALLOW_REPO_OVERRIDE=1 _is_whitelisted "secrets" "any/path/secret.js" 2>/dev/null; then res="skipped"; else res="checked"; fi
assert_eq "broad glob '*' is rejected" "checked" "$res"
teardown_sandbox

# --- substring guard match closed: 'docker_runner' must not match 'docker_run' ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
whitelist:
  - file: "x.txt"
    guard: docker_runner
    reason: "different guard"
YAML
_load_whitelist "iron-dome.yml"
res=""
if _is_whitelisted "docker_run" "x.txt" 2>/dev/null; then res="skipped"; else res="checked"; fi
assert_eq "substring guard match no longer leaks across guards" "checked" "$res"
teardown_sandbox

# --- json-validate.sh does not execute code embedded in a filename (C2) ---
if command -v python3 >/dev/null 2>&1; then
  setup_sandbox
  # A filename that WOULD run `touch CANARY_2761` if interpolated into python -c.
  mal_name="x'+__import__('os').system('touch CANARY_2761')+'.json"
  : > "$mal_name"
  bash "$PROJECT_ROOT/src/ci/json-validate.sh" >/dev/null 2>&1 || true
  canary="absent"; [[ -f CANARY_2761 ]] && canary="created"
  assert_eq "filename injection does not execute (no canary)" "absent" "$canary"
  teardown_sandbox

  # functional: valid JSON passes, invalid JSON fails
  setup_sandbox
  echo '{"ok": true}' > good.json
  assert_exit_code "valid JSON passes" "0" bash "$PROJECT_ROOT/src/ci/json-validate.sh" good.json
  echo 'not json' > bad.json
  assert_exit_code "invalid JSON fails" "1" bash "$PROJECT_ROOT/src/ci/json-validate.sh" bad.json
  teardown_sandbox
fi
