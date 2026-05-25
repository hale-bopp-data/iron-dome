#!/usr/bin/env bash
# Iron Dome Tests — Pattern Coverage (true positives for core secret patterns)
# Complements test_secrets.sh, which already covers the other core patterns.
# Secret-like fixtures are assembled at runtime (string-split) so the committed
# source carries no literal token for the pre-commit scanner to flag, while the
# sandbox file still receives the real value for guard_secrets to detect.
# PBI #428.

suite "Pattern Coverage"

_pc() { # $1 desc, $2 expected-name, $3 fixture-line
  setup_sandbox
  reload_core
  printf '%s\n' "$3" > fixture.txt
  local out
  out=$(guard_secrets "fixture.txt" 2>&1 || true)
  assert_contains "$1" "$2" "$out"
  teardown_sandbox
}

_pc "detects GitLab token"        "GitLab Token"            'gl = "glpat-aBcDeFgHiJkLmNoPqRsT"'
_pc "detects AWS secret key"      "AWS Secret Key"          'aws_secret_access_key=aJ7kP2qR9sT4uV6wX1yZ3bC5dE8fG0hI2jK4lM6n'
_pc "detects OpenAI/OpenRouter"   "OpenAI / OpenRouter Key" "k = sk""-aBcDeFgHiJkLmNoPqRsTuV"
_pc "detects Qdrant API key"      "Qdrant API Key"          "qdrant_api_""key = \"aBcDeFgHiJkLmNoPqRsT\""
_pc "detects Generic API key"     "Generic API Key"         "api_""key = \"aBcDeFgHiJkLmNoPqRsT\""
_pc "detects Generic Secret"      "Generic Secret"          "sec""ret = \"aBcDeFgHiJkLmNoPqRsT\""

# longer fixtures built with printf to avoid hand-count drift
setup_sandbox; reload_core
echo "ado=$(printf 'a%.0s' {1..52})JQQJ99Cabcdef" > ado.txt
out=$(guard_secrets "ado.txt" 2>&1 || true)
assert_contains "detects Azure DevOps PAT" "Azure DevOps PAT" "$out"
teardown_sandbox

setup_sandbox; reload_core
echo "n8n_api_$(printf '0%.0s' {1..60})" > n8n.txt
out=$(guard_secrets "n8n.txt" 2>&1 || true)
assert_contains "detects N8N API key" "N8N API Key" "$out"
teardown_sandbox

setup_sandbox; reload_core
echo "g = AIzaSy$(printf 'A%.0s' {1..33})" > g.txt
out=$(guard_secrets "g.txt" 2>&1 || true)
assert_contains "detects Google/Gemini API key" "Google/Gemini API Key" "$out"
teardown_sandbox