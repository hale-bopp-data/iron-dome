#!/usr/bin/env bash
# ============================================================================
# Iron Dome Guard: Lockfile Sync (G-CI-6)
# ============================================================================
# Blocks commits where package.json is staged but package-lock.json is not
# (or vice versa). Desync causes npm ci to fail in CI.
#
# Trigger: staged package.json or package-lock.json (one without the other)
# Severity: BLOCKING
# ============================================================================

guard_lockfile_sync() {
  # This is a repo-level guard, not per-file
  # Called once from pre-commit hook after the per-file loop

  local staged_files="$1"

  local has_pkg_json=false
  local has_pkg_lock=false

  while IFS= read -r file; do
    [[ "$(basename "$file")" == "package.json" ]] && has_pkg_json=true
    [[ "$(basename "$file")" == "package-lock.json" ]] && has_pkg_lock=true
  done <<< "$staged_files"

  # If neither is staged, nothing to check
  if ! $has_pkg_json && ! $has_pkg_lock; then
    return 0
  fi

  # If both are staged, all good
  if $has_pkg_json && $has_pkg_lock; then
    return 0
  fi

  # One without the other = desync risk
  if $has_pkg_json && ! $has_pkg_lock; then
    echo "  LOCKFILE_SYNC: package.json staged without package-lock.json"
    echo "  FIX: npm install && git add package-lock.json"
    _report_finding "LOCKFILE_SYNC" "package.json without package-lock.json" "package.json" "0"
    return 1
  fi

  # package-lock.json alone is OK (e.g., npm audit fix only touches lock)
  return 0
}
