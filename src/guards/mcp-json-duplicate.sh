#!/usr/bin/env bash
# Iron Dome — MCP Config Drift Guard (G22)
# Blocks commits of .mcp.json in subdirectories.
# SSoT: root .mcp.json only.
#
# Origin: EasyWay S245 — MCP config fragmentation prevention.
# PBI #1647 — G22 cross-agent enforcement.

guard_mcp_json_duplicate() {
  local file="$1"

  if _is_whitelisted "mcp_json_duplicate" "$file"; then return 0; fi

  # Allow root .mcp.json (SSoT)
  if [[ "$file" == ".mcp.json" ]]; then return 0; fi

  # Block any .mcp.json in subdirectory
  if [[ "$file" =~ \.mcp\.json$ ]]; then
    _report_finding "MCP_DRIFT" "Duplicate .mcp.json" "$file" "1"
    IRON_DOME_OTHER_FOUND=$((IRON_DOME_OTHER_FOUND + 1))
    _guard_log "mcp_json_duplicate" "blocking" "duplicate .mcp.json at $file"
    return 1
  fi

  return 0
}
