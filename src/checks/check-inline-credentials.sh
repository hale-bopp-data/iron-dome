#!/usr/bin/env bash
# ============================================================================
# Iron Dome Check: Inline Credentials in .git/config
# ============================================================================
# Cross-repo scan: detects credentials embedded in Git remote URLs.
# Pattern: https?://[^/]*:[^@]+@ (user:password@host in remote URLs)
#
# Usage:
#   check-inline-credentials.sh [--factory-vcs PATH] [REPO_PATH ...]
#   check-inline-credentials.sh /path/to/repo1 /path/to/repo2
#   check-inline-credentials.sh --factory-vcs /c/EW/easyway/infra/factory-vcs.json
#
# Exit codes:
#   0 = no inline credentials found
#   1 = inline credentials detected (blocks deploy)
#   2 = no repos to scan (config error)
#
# Telemetry: appends JSONL to IRON_DOME_TELEMETRY_FILE or default location.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IRON_DOME_ROOT="$(dirname "$SCRIPT_DIR")"

# Source core for telemetry + version
if [[ -f "$IRON_DOME_ROOT/src/iron-dome-core.sh" ]]; then
  source "$IRON_DOME_ROOT/src/iron-dome-core.sh"
else
  IRON_DOME_VERSION="unknown"
fi

# --- Config ---
CRED_PATTERN='https?://[^/[:space:]]*:[^@[:space:]]+@'
TELEMETRY_FILE="${IRON_DOME_TELEMETRY_FILE:-/var/log/easyway/iron-dome.jsonl}"
FACTORY_VCS=""
REPO_PATHS=()
VERBOSE="${IRON_DOME_VERBOSE:-0}"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --factory-vcs)
      FACTORY_VCS="$2"
      shift 2
      ;;
    --telemetry-file)
      TELEMETRY_FILE="$2"
      shift 2
      ;;
    --verbose|-v)
      VERBOSE=1
      shift
      ;;
    --help|-h)
      echo "Usage: check-inline-credentials.sh [--factory-vcs PATH] [REPO_PATH ...]"
      echo "  Scans .git/config of repos for embedded credentials in remote URLs."
      echo ""
      echo "Options:"
      echo "  --factory-vcs PATH   Read repo list from factory-vcs.json"
      echo "  --telemetry-file P   Write JSONL telemetry to P (default: /var/log/easyway/iron-dome.jsonl)"
      echo "  --verbose, -v        Verbose output"
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      exit 2
      ;;
    *)
      REPO_PATHS+=("$1")
      shift
      ;;
  esac
done

# --- Resolve repo list from factory-vcs.json ---
if [[ -n "$FACTORY_VCS" ]]; then
  if [[ ! -f "$FACTORY_VCS" ]]; then
    echo "ERROR: factory-vcs.json not found: $FACTORY_VCS" >&2
    exit 2
  fi
  # Extract local_path from each repo entry (requires jq or node)
  if command -v jq &>/dev/null; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && REPO_PATHS+=("$p")
    done < <(jq -r '.repos | to_entries[] | .value.local_path // empty' "$FACTORY_VCS" 2>/dev/null)
  elif command -v node &>/dev/null; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && REPO_PATHS+=("$p")
    done < <(node -e "
      const f = require('$FACTORY_VCS');
      for (const v of Object.values(f.repos || {})) {
        if (v.local_path) console.log(v.local_path);
      }
    " 2>/dev/null)
  else
    echo "ERROR: jq or node required to parse factory-vcs.json" >&2
    exit 2
  fi
fi

if [[ ${#REPO_PATHS[@]} -eq 0 ]]; then
  echo "ERROR: No repos to scan. Provide paths or --factory-vcs." >&2
  exit 2
fi

# --- Telemetry helper ---
_log_telemetry() {
  local repo="$1" severity="$2" detail="$3"
  local ts caller
  ts=$(date -Is 2>/dev/null || date +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo "unknown")
  caller=$(whoami 2>/dev/null || echo "unknown")

  local telemetry_dir
  telemetry_dir=$(dirname "$TELEMETRY_FILE")
  mkdir -p "$telemetry_dir" 2>/dev/null || true

  # Escape JSON
  local json_detail
  json_detail=$(printf '%s' "$detail" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' 2>/dev/null || echo "$detail")

  printf '{"ts":"%s","guard":"inline_credentials","repo":"%s","severity":"%s","detail":"%s","caller":"%s","version":"%s"}\n' \
    "$ts" "$repo" "$severity" "$json_detail" "$caller" "${IRON_DOME_VERSION:-unknown}" \
    >> "$TELEMETRY_FILE" 2>/dev/null || true
}

# --- Scan ---
TOTAL=0
TAINTED=0
SKIPPED=0
FINDINGS=()

for repo_path in "${REPO_PATHS[@]}"; do
  TOTAL=$((TOTAL + 1))
  git_config="$repo_path/.git/config"

  if [[ ! -f "$git_config" ]]; then
    [[ "$VERBOSE" == "1" ]] && echo "  SKIP: $repo_path (no .git/config)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  repo_name=$(basename "$repo_path")

  # Scan for inline credentials pattern
  matches=$(grep -nP "$CRED_PATTERN" "$git_config" 2>/dev/null || true)

  if [[ -n "$matches" ]]; then
    TAINTED=$((TAINTED + 1))
    # Report each match (redact the credential portion)
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      line_num="${match_line%%:*}"
      # Redact: replace password portion with ***
      redacted=$(echo "$match_line" | sed -E 's|(https?://[^/[:space:]]*):([^@[:space:]]+)@|\1:***@|g')
      FINDINGS+=("INLINE_CRED [$repo_name] .git/config:$line_num $redacted")
      echo "  FOUND: $repo_name .git/config:$line_num (credential in remote URL)"
      _log_telemetry "$repo_name" "blocking" ".git/config:$line_num inline credential in remote URL"
    done <<< "$matches"
  else
    [[ "$VERBOSE" == "1" ]] && echo "  OK: $repo_name"
    _log_telemetry "$repo_name" "ok" "clean"
  fi
done

# --- Report ---
echo ""
echo "--- Iron Dome: Inline Credentials Check ---"
echo "Repos scanned:  $TOTAL"
echo "Skipped:        $SKIPPED"
echo "Clean:          $((TOTAL - TAINTED - SKIPPED))"
echo "Tainted:        $TAINTED"
echo "Findings:       ${#FINDINGS[@]}"
echo "--------------------------------------------"

if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  echo ""
  echo "FINDINGS:"
  for f in "${FINDINGS[@]}"; do
    echo "  - $f"
  done
  echo ""
  echo "ACTION: Remove inline credentials from .git/config."
  echo "  Fix: git remote set-url origin <url-without-credentials>"
  echo "  Ref: S285, S294 — inline creds leak via mirror/clone."
  exit 1
fi

exit 0
