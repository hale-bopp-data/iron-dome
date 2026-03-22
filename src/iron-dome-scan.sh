#!/usr/bin/env bash
# ============================================================================
# Iron Dome Scanner — File scanner for CI and manual use
# ============================================================================
# Scans files for secrets, conflict markers, and policy violations.
# Used by: CI pipelines (server-side), `iron-dome scan` CLI command.
#
# Usage:
#   iron-dome-scan.sh [--changed-only] [--all] [--verbose] [--base-ref REF]
#
# Exit codes:
#   0 = clean
#   1 = blocking findings (secrets, conflicts, policy violations)
#   2 = advisory findings only (debt, encoding, etc.)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/iron-dome-core.sh"
_load_guards

# --- Options ---
CHANGED_ONLY=true
BASE_REF="origin/main"
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed-only) CHANGED_ONLY=true; shift ;;
    --all)          CHANGED_ONLY=false; shift ;;
    --base-ref)     BASE_REF="$2"; shift 2 ;;
    --verbose)      VERBOSE=true; shift ;;
    -h|--help)
      echo "Iron Dome Scanner v${IRON_DOME_VERSION}"
      echo "Usage: iron-dome-scan.sh [--changed-only|--all] [--base-ref REF] [--verbose]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 99 ;;
  esac
done

# --- Collect files ---
_get_files() {
  if $CHANGED_ONLY; then
    # In CI PR pipeline
    if [[ -n "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}" ]]; then
      local target_ref="origin/${SYSTEM_PULLREQUEST_TARGETBRANCH#refs/heads/}"
      git diff --name-only --diff-filter=ACMR "$target_ref"...HEAD 2>/dev/null || \
        git diff --name-only --diff-filter=ACMR "$BASE_REF"...HEAD 2>/dev/null || \
        git diff --name-only --diff-filter=ACMR HEAD~1 HEAD 2>/dev/null || true
    # GitHub Actions PR
    elif [[ -n "${GITHUB_BASE_REF:-}" ]]; then
      git diff --name-only --diff-filter=ACMR "origin/${GITHUB_BASE_REF}"...HEAD 2>/dev/null || \
        git diff --name-only --diff-filter=ACMR HEAD~1 HEAD 2>/dev/null || true
    else
      git diff --name-only --diff-filter=ACMR "$BASE_REF"...HEAD 2>/dev/null || \
        git diff --name-only --diff-filter=ACMR HEAD~1 HEAD 2>/dev/null || true
    fi
  else
    find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' | sed 's|^\./||'
  fi
}

# --- Main ---
main() {
  echo "============================================"
  echo "  Iron Dome v${IRON_DOME_VERSION} — Scanner"
  echo "============================================"
  echo ""

  local files
  files=$(_get_files)

  if [[ -z "$files" ]]; then
    echo "No files to scan. Clean."
    exit 0
  fi

  local file_count=0
  local scanned_count=0

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    file_count=$((file_count + 1))

    if _should_skip_file "$file"; then
      $VERBOSE && echo "  SKIP: $file"
      continue
    fi

    [[ ! -f "$file" ]] && continue

    $VERBOSE && echo "  SCAN: $file"
    scanned_count=$((scanned_count + 1))

    # Run enabled guards (respects iron-dome.yml config)
    _is_guard_enabled "secrets" && guard_secrets "$file" || true
    _is_guard_enabled "conflict_markers" && guard_conflict_markers "$file" || true
    _is_guard_enabled "docker_run" && type guard_docker_run &>/dev/null && guard_docker_run "$file" || true
    _is_guard_enabled "large_file" && type guard_large_file &>/dev/null && guard_large_file "$file" || true
    _is_guard_enabled "sensitive_files" && type guard_sensitive_files &>/dev/null && guard_sensitive_files "$file" || true
    _is_guard_enabled "debt" && type guard_debt &>/dev/null && guard_debt "$file" || true

  done <<< "$files"

  echo ""
  echo "Files in changeset: $file_count"
  echo "Files scanned:      $scanned_count"

  _print_report

  # Log to telemetry
  local total_blocking=$((IRON_DOME_SECRETS_FOUND + IRON_DOME_CONFLICTS_FOUND + IRON_DOME_DOCKER_FOUND + IRON_DOME_OTHER_FOUND))

  if [[ $total_blocking -gt 0 ]]; then
    _guard_log "scanner" "blocking" "${total_blocking} blocking finding(s)"

    # CI integration: fail the build
    if [[ -n "${BUILD_BUILDID:-}" ]]; then
      echo "##vso[task.complete result=Failed;]Iron Dome: ${total_blocking} violation(s)"
    fi

    exit 1
  elif [[ $IRON_DOME_ADVISORY_FOUND -gt 0 ]]; then
    _guard_log "scanner" "advisory" "${IRON_DOME_ADVISORY_FOUND} advisory finding(s)"
    exit 2
  else
    if [[ -n "${BUILD_BUILDID:-}" ]]; then
      echo "##vso[task.complete result=Succeeded;]Iron Dome: clean"
    fi
    exit 0
  fi
}

main "$@"
