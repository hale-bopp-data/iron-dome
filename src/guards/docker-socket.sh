#!/usr/bin/env bash
# Iron Dome Guard: Docker Socket Mount
# Hook: pre-commit
# Default: opt-in
#
# Detects docker.sock mounts in docker-compose files and Dockerfiles.
# docker.sock access allows container escape and full host compromise,
# even with :ro (read-only) flag.

guard_docker_socket() {
  local file="$1"

  # Only scan compose/docker files
  case "$file" in
    *docker-compose*|*Dockerfile*|*.yml|*.yaml) ;;
    *) return 0 ;;
  esac

  if _is_whitelisted "docker_socket" "$file"; then return 0; fi

  local found=0

  # Pattern: docker.sock mount (with or without :ro)
  local p1='/var/run/docker\.sock'
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p1" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_num="${match_line%%:*}"
    _report_finding "DOCKER_SOCK" "docker.sock mount (container escape risk)" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
