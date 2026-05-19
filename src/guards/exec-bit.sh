#!/usr/bin/env bash
# Iron Dome — Script Exec Bit Guard
# Blocks commits where .sh files in executable paths have mode 100644.
# Prevents silent cron/systemd failures from Windows-committed scripts.
#
# Origin: EasyWay S350-S352 incident (cron silent 44 days, missing chmod +x).
# PBI #1364.
#
# Escape hatch: SCRIPT_EXEC_SKIP=1

guard_exec_bit() {
  local file="$1"

  if _is_whitelisted "exec_bit" "$file"; then return 0; fi
  [[ "${SCRIPT_EXEC_SKIP:-}" == "1" ]] && return 0

  # Only .sh files
  [[ ! "$file" =~ \.sh$ ]] && return 0

  # Only executable paths (configurable via env, fallback to common locations)
  local required_paths="${EXEC_REQUIRED_PATHS:-scripts/linux/|scripts/ops/|scripts/infra/|scripts/bin/|scripts/git-hooks/|scripts/hooks/|scripts/validate/|scripts/credentials/|release/scripts/|src/hooks/|src/guards/}"
  [[ ! "$file" =~ $required_paths ]] && return 0

  local mode
  mode=$(git ls-files --stage -- "$file" 2>/dev/null | awk '{print $1}' || echo "")
  if [[ "$mode" == "100644" ]]; then
    _report_finding "EXEC_BIT" "Missing executable bit (mode 100644)" "$file" "1"
    IRON_DOME_OTHER_FOUND=$((IRON_DOME_OTHER_FOUND + 1))
    _guard_log "exec_bit" "blocking" "$file: mode 100644 should be 100755"
    return 1
  fi

  return 0
}
