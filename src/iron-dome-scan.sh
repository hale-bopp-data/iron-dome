#!/usr/bin/env bash
# ============================================================================
# Iron Dome Scanner — File scanner for CI and manual use
# ============================================================================
# Guards: secrets, conflict markers, docker run, large file, sensitive file,
#         encoding, path length, debt (advisory),
#         local links (G-CI-3), untracked imports (G-CI-5), lockfile sync (G-CI-6),
#         exec injection (S244), innerHTML XSS (S244), db credentials (S244),
#         docker socket (S244), bind all interfaces (S244),
#         jwt dev bypass (S244), cors wildcard (S244), webhook no auth (S244),
#         eval injection (S244).
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
  local ERRORS=0

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    file_count=$((file_count + 1))

    [[ ! -f "$file" ]] && continue

    # Sensitive file guard (checks filename, not content)
    if _is_guard_enabled "sensitive_files" && type guard_sensitive_files &>/dev/null; then
      guard_sensitive_files "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Large file guard
    if _is_guard_enabled "large_file" && type guard_large_file &>/dev/null; then
      guard_large_file "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Path length guard (PBI #516)
    if _is_guard_enabled "path_length" && type guard_path_length &>/dev/null; then
      guard_path_length "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Encoding guard (PBI #515)
    if _is_guard_enabled "encoding" && type guard_encoding &>/dev/null; then
      guard_encoding "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Skip binary/large for content scanning
    if _should_skip_file "$file"; then
      $VERBOSE && echo "  SKIP: $file"
      continue
    fi

    $VERBOSE && echo "  SCAN: $file"
    scanned_count=$((scanned_count + 1))

    # Run enabled guards (respects iron-dome.yml config)

    # Secrets scan
    _is_guard_enabled "secrets" && guard_secrets "$file" || true

    # Conflict markers
    _is_guard_enabled "conflict_markers" && guard_conflict_markers "$file" || true

    # Docker run guard
    _is_guard_enabled "docker_run" && type guard_docker_run &>/dev/null && guard_docker_run "$file" || true

    # Command injection guard (execSync with interpolation)
    if _is_guard_enabled "exec_injection" && type guard_exec_injection &>/dev/null; then
      guard_exec_injection "$file" || ERRORS=$((ERRORS + 1))
    fi

    # XSS guard (innerHTML with dynamic content)
    if _is_guard_enabled "innerhtml_xss" && type guard_innerhtml_xss &>/dev/null; then
      guard_innerhtml_xss "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Database credentials guard (hardcoded connection strings)
    if _is_guard_enabled "db_credentials" && type guard_db_credentials &>/dev/null; then
      guard_db_credentials "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Docker socket guard (docker.sock mounts)
    if _is_guard_enabled "docker_socket" && type guard_docker_socket &>/dev/null; then
      guard_docker_socket "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Bind all interfaces guard (0.0.0.0 exposure)
    if _is_guard_enabled "bind_all" && type guard_bind_all &>/dev/null; then
      guard_bind_all "$file" || ERRORS=$((ERRORS + 1))
    fi

    # JWT dev bypass guard (auth disabled by NODE_ENV)
    if _is_guard_enabled "jwt_dev_bypass" && type guard_jwt_dev_bypass &>/dev/null; then
      guard_jwt_dev_bypass "$file" || ERRORS=$((ERRORS + 1))
    fi

    # CORS wildcard guard
    if _is_guard_enabled "cors_wildcard" && type guard_cors_wildcard &>/dev/null; then
      guard_cors_wildcard "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Webhook without auth guard
    if _is_guard_enabled "webhook_no_auth" && type guard_webhook_no_auth &>/dev/null; then
      guard_webhook_no_auth "$file" || ERRORS=$((ERRORS + 1))
    fi

    # eval/Function injection guard
    if _is_guard_enabled "eval_injection" && type guard_eval_injection &>/dev/null; then
      guard_eval_injection "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Debt guard (advisory — never blocks)
    _is_guard_enabled "debt" && type guard_debt &>/dev/null && guard_debt "$file" || true

    # Local links guard (G-CI-3) — checks package-lock.json for symlinks
    if _is_guard_enabled "local_links" && type guard_local_links &>/dev/null; then
      guard_local_links "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Untracked imports guard (G-CI-5) — checks relative imports to untracked files
    if _is_guard_enabled "untracked_imports" && type guard_untracked_imports &>/dev/null; then
      guard_untracked_imports "$file" || ERRORS=$((ERRORS + 1))
    fi

    # === v2.2.0 EW-ported guards ===

    # MCP config duplicate guard (G22)
    if _is_guard_enabled "mcp_json_duplicate" && type guard_mcp_json_duplicate &>/dev/null; then
      guard_mcp_json_duplicate "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Inline credentials in URL guard (S285)
    if _is_guard_enabled "inline_credentials" && type guard_inline_credentials &>/dev/null; then
      guard_inline_credentials "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Script exec bit guard (S519)
    if _is_guard_enabled "exec_bit" && type guard_exec_bit &>/dev/null; then
      guard_exec_bit "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Env secrets source guard
    if _is_guard_enabled "env_secrets_source" && type guard_env_secrets_source &>/dev/null; then
      guard_env_secrets_source "$file" || ERRORS=$((ERRORS + 1))
    fi

    # Git garbage auto-fix guard (S242)
    _is_guard_enabled "git_garbage" && type guard_git_garbage &>/dev/null && guard_git_garbage "$file" || true

    # Anti-hardcoded audit (G16 Presa Elettrica — advisory by default)
    _is_guard_enabled "anti_hardcoded" && type guard_anti_hardcoded &>/dev/null && guard_anti_hardcoded "$file" || true

  done <<< "$files"

  # --- Repo-level guards (run once, not per file) ---

  # Lockfile sync guard (G-CI-6) — package.json without package-lock.json
  if _is_guard_enabled "lockfile_sync" && type guard_lockfile_sync &>/dev/null; then
    guard_lockfile_sync "$files" || ERRORS=$((ERRORS + 1))
  fi

  # Coupling guard (if changed A, must change B) — repo-level, advisory
  if _is_guard_enabled "coupling" && type guard_coupling &>/dev/null; then
    guard_coupling "$files" || ERRORS=$((ERRORS + 1))
  fi

  # Worktree discipline guard (G28) — repo-level
  if _is_guard_enabled "worktree_discipline" && type guard_worktree_discipline_finalize &>/dev/null; then
    guard_worktree_discipline_finalize || ERRORS=$((ERRORS + 1))
  fi

  # WI-Link auto-prepend guard (G26) — repo-level, runs LAST (modifies COMMIT_EDITMSG)
  if _is_guard_enabled "wi_link" && type guard_wi_link_finalize &>/dev/null; then
    guard_wi_link_finalize || true
  fi

  echo ""
  echo "Files in changeset: $file_count"
  echo "Files scanned:      $scanned_count"

  _print_report

  # Log to telemetry
  local total_blocking=$((IRON_DOME_SECRETS_FOUND + IRON_DOME_CONFLICTS_FOUND + IRON_DOME_DOCKER_FOUND + IRON_DOME_OTHER_FOUND + ERRORS))

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
