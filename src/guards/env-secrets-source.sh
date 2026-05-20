#!/usr/bin/env bash
# Iron Dome — Env Secrets Source Guard
# Blocks commits that add `source .env.secrets` or `. .env.secrets` patterns.
# Direct sourcing is fragile: fails silently if file missing, exposes all vars.
#
# Origin: EasyWay PBI #1364 — canonical: secrets-read <KEY> runtime helper.
#
# Escape hatch: ENV_SECRETS_SKIP=1

guard_env_secrets_source() {
  local file="$1"

  if _is_whitelisted "env_secrets_source" "$file"; then return 0; fi
  [[ "${ENV_SECRETS_SKIP:-}" == "1" ]] && return 0

  [[ "$file" =~ $IRON_DOME_BINARY_SKIP ]] && return 0
  [[ "$file" =~ git-hooks/(pre-commit|pre-push)$ ]] && return 0
  [[ "$file" =~ iron-dome.*\.(sh|py)$ ]] && return 0

  local pattern='(source|\.)\s+.*\.env\.secrets'

  local matches
  matches=$(git diff --cached -- "$file" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E "$pattern" 2>/dev/null || true)
  [[ -z "$matches" ]] && return 0

  _report_finding "ENV_SECRETS_SOURCE" "Direct .env.secrets sourcing" "$file" "1"
  IRON_DOME_OTHER_FOUND=$((IRON_DOME_OTHER_FOUND + 1))
  _guard_log "env_secrets_source" "blocking" "$file: source .env.secrets detected (use secrets-read instead)"
  return 1
}
