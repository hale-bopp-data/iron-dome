#!/usr/bin/env bash
# Iron Dome Guard: Webhook Without Authentication
# Hook: pre-commit
# Default: opt-in
#
# Detects webhook endpoints that don't verify signatures (HMAC, shared secret).
# Unauthenticated webhooks allow anyone to trigger deployments, pipelines,
# or agent actions if they discover the URL.
#
# GEDI Black Swan: "Se questa difesa viene bypassata, il sistema collassa?"

guard_webhook_no_auth() {
  local file="$1"

  case "$file" in
    *.js|*.mjs|*.cjs|*.ts|*.mts|*.py|*.sh|*.bash) ;;
    *) return 0 ;;
  esac

  if _is_whitelisted "webhook_no_auth" "$file"; then return 0; fi

  local found=0

  # Pattern 1: webhook route/handler without signature/secret/hmac nearby
  # First find webhook endpoints
  local p1='(webhook|hook|callback)\s*[=:(]|/(webhook|hook|deploy/webhook|api/webhook)'
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p1" "$file" 2>/dev/null || true)

  if [[ -n "$matches" ]]; then
    # Check if file has ANY signature verification
    local has_auth
    has_auth=$(LC_ALL=en_US.UTF-8 grep -cP '(hmac|signature|verify|secret|x-hub-signature|x-ado-signature|webhook.secret|WEBHOOK_SECRET)' "$file" 2>/dev/null | head -1 || echo "0")
    has_auth="${has_auth:-0}"
    has_auth="${has_auth%%[^0-9]*}"

    if [[ "${has_auth:-0}" -eq 0 ]]; then
      while IFS= read -r match_line; do
        [[ -z "$match_line" ]] && continue
        local line_content="${match_line#*:}"
        # Skip comments and imports
        if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '^\s*(#|//|import|from|require)' 2>/dev/null; then continue; fi
        local line_num="${match_line%%:*}"
        _report_finding "WEBHOOK" "Webhook handler without signature verification" "$file" "$line_num"
        found=$((found + 1))
      done <<< "$matches"
    fi
  fi

  # Pattern 2: Optional/skippable webhook secret (secret || "", if !secret skip)
  local p2='WEBHOOK_SECRET\s*\|\|\s*["\x27]["\x27]|if\s*\(\s*!.*[Ss]ecret\s*\)\s*(return|continue|skip)'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p2" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "WEBHOOK" "Webhook secret is optional (should be mandatory)" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
