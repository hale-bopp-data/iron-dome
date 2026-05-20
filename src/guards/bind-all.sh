#!/usr/bin/env bash
# Iron Dome Guard: Bind All Interfaces (0.0.0.0)
# Hook: pre-commit
# Default: opt-in
#
# Detects services binding to 0.0.0.0 in config/compose/server files.
# Binding to all interfaces exposes services to the network, bypassing
# reverse proxy auth (Caddy, Nginx, Traefik).
# Safe alternative: 127.0.0.1 or localhost.

guard_bind_all() {
  local file="$1"

  # Only scan relevant config files
  case "$file" in
    *docker-compose*|*Dockerfile*|*.yml|*.yaml|*.json|*.js|*.mjs|*.ts|*.toml|*.conf|*.cfg|*Caddyfile*) ;;
    *) return 0 ;;
  esac

  if _is_whitelisted "bind_all" "$file"; then return 0; fi

  local found=0

  # Pattern 1: 0.0.0.0:<port> in compose/config (e.g. "0.0.0.0:3200")
  local p1='0\.0\.0\.0:[0-9]+'
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p1" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    # Skip comments
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '^\s*#' 2>/dev/null; then
      continue
    fi
    local line_num="${match_line%%:*}"
    _report_finding "BIND_ALL" "Service binding to 0.0.0.0 (all interfaces)" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 2: --host 0.0.0.0 in Dockerfile CMD/ENTRYPOINT
  local p2='--host\s+0\.0\.0\.0'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p2" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "BIND_ALL" "--host 0.0.0.0 in container CMD" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
