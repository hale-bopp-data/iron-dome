#!/usr/bin/env bash
# Iron Dome Tests — Per-Repo Override (.iron-dome.yml): disabled_patterns + additional_patterns
# PBI #428.
#
# NOTE: _load_config only reads the .iron-dome.yml override when a main iron-dome.yml
# is present (core.sh returns early otherwise). Each block writes a minimal main config.
# Secret-like fixtures are assembled at runtime ("gh""p" split) so the committed source
# carries no literal token for the pre-commit scanner to flag.

suite "Per-Repo Override"

# SEC #2761: disabled_patterns / additional_patterns from an in-repo
# .iron-dome.yml are honored only under the explicit local opt-in (the scanned
# tree is untrusted in CI). These tests exercise the feature, so opt in here;
# test_security_2761.sh asserts the bypass is closed WITHOUT the opt-in.
export IRON_DOME_ALLOW_REPO_OVERRIDE=1

_min_config() { printf 'guards:\n  secrets:\n    enabled: true\n' > iron-dome.yml; }
GHP="gh""p_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"   # -> ghp_<36> at runtime only

# --- disabled_patterns: suppress a named core pattern ---
setup_sandbox
reload_core
_min_config
printf 'disabled_patterns:\n  - "GitHub PAT"\n' > .iron-dome.yml
_load_config
# fixture matches ONLY GitHub PAT (no token/quotes that would also trip Generic Secret)
echo "gh = $GHP" > app.js
guard_secrets "app.js" >/dev/null 2>&1 || true
assert_eq "disabled_patterns suppresses GitHub PAT" "0" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox

# --- disabled one pattern, a different one still fires ---
setup_sandbox
reload_core
_min_config
printf 'disabled_patterns:\n  - "GitHub PAT"\n' > .iron-dome.yml
_load_config
echo 'gl = "glpat-aBcDeFgHiJkLmNoPqRsT"' > tok.txt
guard_secrets "tok.txt" >/dev/null 2>&1 || true
assert_eq "non-disabled pattern still fires under override" "1" "$IRON_DOME_SECRETS_FOUND"
teardown_sandbox

# --- additional_patterns: a custom pattern is detected ---
setup_sandbox
reload_core
_min_config
printf "additional_patterns:\n  - name: \"Acme Token\"\n    pattern: 'acme_[a-z0-9]{12}'\n    severity: high\n" > .iron-dome.yml
_load_config
echo 'val = acme_abc123def456' > svc.py
out=$(guard_secrets "svc.py" 2>&1 || true)
assert_contains "additional_patterns detects custom token" "Acme Token" "$out"
teardown_sandbox

# --- additional_patterns: defaults still active alongside custom ---
setup_sandbox
reload_core
_min_config
printf "additional_patterns:\n  - name: \"Acme Token\"\n    pattern: 'acme_[a-z0-9]{12}'\n" > .iron-dome.yml
_load_config
echo "k = \"$GHP\"" > d.js
out=$(guard_secrets "d.js" 2>&1 || true)
assert_contains "default GitHub PAT still detected with additional_patterns present" "GitHub PAT" "$out"
teardown_sandbox

# SEC #2761: do not leak the opt-in into later test files (sourced in the same shell).
unset IRON_DOME_ALLOW_REPO_OVERRIDE