#!/usr/bin/env bash
# ============================================================================
# Iron Dome Core — Shared functions for all guards
# ============================================================================
# Loaded by hooks, scanner, and CLI.
# Provides: config loading, finding reporting, telemetry, safe-match checking.
#
# The Dumb Guard: no AI, no LLM — pure enforcement.
# ============================================================================

set -euo pipefail

IRON_DOME_VERSION="2.3.0"

# --- Global state ---
IRON_DOME_FINDINGS=()
IRON_DOME_SECRETS_FOUND=0
IRON_DOME_CONFLICTS_FOUND=0
IRON_DOME_DOCKER_FOUND=0
IRON_DOME_OTHER_FOUND=0
IRON_DOME_ADVISORY_FOUND=0

# --- Secret patterns (loaded from config or defaults) ---
IRON_DOME_SECRET_PATTERNS=(
  "Private Key|||-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"
  "GitHub PAT|||ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{60,}"
  "GitLab Token|||glpat-[A-Za-z0-9\-_]{20,}"
  "AWS Access Key|||AKIA[0-9A-Z]{16}"
  "AWS Secret Key|||(aws_secret_access_key)\s*[:=]\s*[A-Za-z0-9/+=]{40}"
  "Azure Connection String|||DefaultEndpointsProtocol=https?;AccountName=[^;]+;AccountKey=[A-Za-z0-9+/=]{40,}"
  "OpenAI / OpenRouter Key|||sk-[a-zA-Z0-9]{20,}"
  "Hardcoded Password|||(password|passwd|pwd)\s*[:=]\s*[\"'][^\"'\$]{8,}[\"']"
  "Generic API Key|||(api[_-]?key|apikey|api[_-]?secret)\s*[:=]\s*[\"'][A-Za-z0-9\-_]{20,}[\"']"
  "Bearer Token|||bearer\s+[A-Za-z0-9\-_\.]{20,}"
  "Generic Secret|||(secret|token|credential)\s*[:=]\s*[\"'][A-Za-z0-9\-_/+=]{20,}[\"']"
  "Azure DevOps PAT|||[A-Za-z0-9]{52}JQQJ99C[A-Za-z0-9]+"
  "Qdrant API Key|||(?i)qdrant[_-]?api[_-]?key\s*[:=]\s*[\"'][A-Za-z0-9]{20,}[\"']"
  "N8N API Key|||n8n_api_[a-f0-9]{60,}"
  "Google/Gemini API Key|||AIzaSy[A-Za-z0-9\-_]{33}"
  "Terraform Password|||(?i)initial_bot_password\s*=|(?i)(password|secret)\s*=\s*\"[^\"$]{8,}\""
)

IRON_DOME_SAFE_PATTERNS=(
  '\$\{[A-Z_][A-Z_0-9]*\}'        # SEC-S218: narrowed from {[A-Z_]+} — require at least 2 chars
  '\$env:[A-Z_][A-Z_0-9]*'        # SEC-S218: narrowed — require named variable
  'process\.env\.[A-Z_][A-Z_0-9]*' # SEC-S218: narrowed from process\.env\. — require named var
  'os\.environ(?:\[|\.get)'       # SEC-S218: narrowed — require access method
  'System\.getenv\s*\('           # SEC-S218: narrowed — require parens
  "env\(\s*[\"']"
  'ChangeMe'
  'placeholder'
  '(?<![A-Za-z0-9])example'
  '<REDACTED>'
  '<PASTE_'
  'your[_-]?api[_-]?key'
  'xxx+'
  '\.env\.example'
  'iron-dome'
  'iron-dome\.yml'
  'iron-dome-core\.sh'
  'iron-dome-scan\.sh'
)

IRON_DOME_DISABLED_PATTERNS=()

# SEC #2761 — Trust boundary. Guards that the IN-REPO config (the working tree
# being scanned) may NOT disable. Only a trusted config sourced from
# IRON_DOME_HOME — outside the scanned tree — can turn these off. Rationale:
# an attacker with PR access must not be able to disable secret detection on
# the same changeset that plants the secret. Set IRON_DOME_ALLOW_REPO_OVERRIDE=1
# to opt back in for local development (never in CI).
IRON_DOME_CRITICAL_GUARDS=(secrets sensitive_files db_credentials inline_credentials)
# Set by _load_config: true when the active config came from a trusted source.
IRON_DOME_CONFIG_TRUSTED=false

IRON_DOME_PROTECTED_BRANCHES=("main" "master")
IRON_DOME_MAX_FILE_KB=1024
IRON_DOME_LARGE_FILE_EXCLUDE=()

# Binary extensions to skip
IRON_DOME_BINARY_SKIP='.*\.(png|jpg|jpeg|gif|ico|woff|woff2|ttf|eot|zip|gz|tar|exe|dll|so|dylib|pdf|svg)$'

# Skip patterns
IRON_DOME_SKIP_PATTERNS=(
  'node_modules/'
  '\.git/'
  'vendor/'
  '__pycache__/'
  '\.venv/'
)

# --- Determine Iron Dome home ---
_iron_dome_home() {
  # 1. Explicit env var
  if [[ -n "${IRON_DOME_HOME:-}" ]]; then
    echo "$IRON_DOME_HOME"
    return
  fi

  # 2. Relative to this script
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # If we're in src/, go up one level
  if [[ "$(basename "$script_dir")" == "src" ]]; then
    echo "$(dirname "$script_dir")"
  else
    echo "$script_dir"
  fi
}

# --- Finding reporter ---
_report_finding() {
  # AC3 fail-loud safety: tolerate underflow caller arity (Bug #2154).
  # Pre-fix, missing $4 with `set -u` aborted the hook mid-scan -> silent
  # false negative. Defaults keep semantics ({type, name, file, line:0}).
  local type="${1:-UNKNOWN}"
  local name="${2:-}"
  local file="${3:-}"
  local line="${4:-0}"

  local finding="${type} [${name}] in ${file}:${line}"
  IRON_DOME_FINDINGS+=("$finding")

  case "$type" in
    SECRET)     IRON_DOME_SECRETS_FOUND=$((IRON_DOME_SECRETS_FOUND + 1)) ;;
    CONFLICT*)  IRON_DOME_CONFLICTS_FOUND=$((IRON_DOME_CONFLICTS_FOUND + 1)) ;;
    DOCKER*)    IRON_DOME_DOCKER_FOUND=$((IRON_DOME_DOCKER_FOUND + 1)) ;;
    DEBT|ENCODING|PATH_LENGTH|AB_MISMATCH)
                IRON_DOME_ADVISORY_FOUND=$((IRON_DOME_ADVISORY_FOUND + 1)) ;;
    *)          IRON_DOME_OTHER_FOUND=$((IRON_DOME_OTHER_FOUND + 1)) ;;
  esac

  # ADO integration: log as build error if in pipeline
  if [[ -n "${BUILD_BUILDID:-}" ]]; then
    echo "##vso[task.logissue type=error]$finding"
  fi

  # GitHub Actions integration
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error file=${file},line=${line}::${type}: ${name}"
  fi

  echo "  FOUND: $finding"
}

# --- Safe match checker ---
# Pre-compiled combined regex for performance (built once, reused)
IRON_DOME_SAFE_REGEX=""

_build_safe_regex() {
  if [[ -n "$IRON_DOME_SAFE_REGEX" ]]; then return; fi
  local joined=""
  for safe in "${IRON_DOME_SAFE_PATTERNS[@]}"; do
    if [[ -n "$joined" ]]; then
      joined="${joined}|${safe}"
    else
      joined="$safe"
    fi
  done
  IRON_DOME_SAFE_REGEX="$joined"
}

_is_safe_match() {
  local line="$1"
  _build_safe_regex
  if echo "$line" | LC_ALL=en_US.UTF-8 grep -qiP "$IRON_DOME_SAFE_REGEX" 2>/dev/null; then
    return 0
  fi
  return 1
}

# --- Pattern disabled checker ---
_is_pattern_disabled() {
  local name="$1"
  for disabled in "${IRON_DOME_DISABLED_PATTERNS[@]}"; do
    if [[ "$name" == "$disabled" ]]; then
      return 0
    fi
  done
  return 1
}

# --- File skip checker ---
_should_skip_file() {
  local file="$1"

  # Binary
  if [[ "$file" =~ $IRON_DOME_BINARY_SKIP ]]; then return 0; fi

  # Skip patterns
  for skip in "${IRON_DOME_SKIP_PATTERNS[@]}"; do
    if [[ "$file" =~ $skip ]]; then return 0; fi
  done

  # File size (scanning limit, not large_file guard)
  if [[ -f "$file" ]]; then
    local size
    size=$(wc -c < "$file" 2>/dev/null || echo 0)
    if [[ "$size" -gt 1048576 ]]; then return 0; fi  # 1MB scan limit (SEC-S218: bumped from 512KB)
  fi

  return 1
}

# --- Guard Telemetry ---
_guard_log() {
  local guard="${1:-unknown}"
  local severity="${2:-advisory}"  # blocking | advisory | bypass | false-positive
  local detail="${3:-}"

  local repo_name branch ts caller telemetry_dir telemetry_file

  repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
  branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  ts=$(date -Is 2>/dev/null || date +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo "unknown")
  caller=$(whoami 2>/dev/null || echo "unknown")

  local session="${IRON_DOME_SESSION:-}"
  local agent="${IRON_DOME_AGENT:-}"

  # Telemetry directory
  telemetry_dir="${IRON_DOME_TELEMETRY_DIR:-${HOME}/.iron-dome}"
  telemetry_file="${telemetry_dir}/telemetry.jsonl"

  mkdir -p "$telemetry_dir" 2>/dev/null || true

  # Escape JSON
  local json_detail
  json_detail=$(printf '%s' "$detail" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' 2>/dev/null || echo "$detail")

  printf '{"ts":"%s","guard":"%s","repo":"%s","severity":"%s","branch":"%s","detail":"%s","caller":"%s","agent":"%s","session":"%s","version":"%s"}\n' \
    "$ts" "$guard" "$repo_name" "$severity" "$branch" "$json_detail" "$caller" "$agent" "$session" "$IRON_DOME_VERSION" \
    >> "$telemetry_file" 2>/dev/null || true
}

# --- Print report ---
_print_report() {
  local total=${#IRON_DOME_FINDINGS[@]}

  echo ""
  echo "--- Iron Dome Report ---"
  echo "Version:            $IRON_DOME_VERSION"
  echo "Secrets found:      $IRON_DOME_SECRETS_FOUND"
  echo "Conflict markers:   $IRON_DOME_CONFLICTS_FOUND"
  echo "Docker violations:  $IRON_DOME_DOCKER_FOUND"
  echo "Other violations:   $IRON_DOME_OTHER_FOUND"
  echo "Advisories:         $IRON_DOME_ADVISORY_FOUND"
  echo "Total findings:     $total"
  echo "------------------------"

  if [[ $total -gt 0 ]]; then
    echo ""
    echo "FINDINGS:"
    for f in "${IRON_DOME_FINDINGS[@]}"; do
      echo "  - $f"
    done
  else
    echo ""
    echo "All clear. No secrets or violations detected."
  fi
}

# --- YAML Config Reader (minimal, no yq dependency) ---
# Reads iron-dome.yml to determine which guards are enabled.
# Populates IRON_DOME_GUARD_ENABLED associative array.

declare -A IRON_DOME_GUARD_ENABLED

_load_config() {
  # Find config file: repo root > IRON_DOME_HOME > defaults
  local config_file=""
  local config_trusted=false
  local repo_root home_dir
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
  home_dir="$(_iron_dome_home)"

  if [[ -f "${repo_root}/iron-dome.yml" ]]; then
    config_file="${repo_root}/iron-dome.yml"
    # SEC #2761 — the repo-root config lives in the scanned tree, so it is
    # untrusted UNLESS iron-dome home IS that repo (scanning its own repo).
    if [[ "$home_dir" -ef "$repo_root" ]]; then config_trusted=true; fi
  elif [[ -f "${home_dir}/iron-dome.yml" ]]; then
    config_file="${home_dir}/iron-dome.yml"
    config_trusted=true
  fi
  IRON_DOME_CONFIG_TRUSTED=$config_trusted

  # Defaults: what's ON if no config file exists
  IRON_DOME_GUARD_ENABLED=(
    [secrets]=true
    [conflict_markers]=true
    [large_file]=true
    [sensitive_files]=true
    [branch_policy]=true
    [docker_run]=false
    [debt]=false
    [semaphore]=false
    [orphan]=false
    [local_links]=true
    [untracked_imports]=true
    [lockfile_sync]=true
    [exec_injection]=true
    [innerhtml_xss]=true
    [db_credentials]=true
    [docker_socket]=false
    [bind_all]=false
    [jwt_dev_bypass]=true
    [cors_wildcard]=true
    [webhook_no_auth]=false
    [eval_injection]=true
    [coupling]=false
  )

  if [[ -z "$config_file" ]]; then
    return 0
  fi

  # Parse enabled/disabled state from YAML
  # Looks for patterns like:
  #   secrets:
  #     enabled: true
  local current_guard=""
  while IFS= read -r line; do
    # Strip carriage return (CRLF on Windows)
    line="${line%$'\r'}"

    local trimmed="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace
    local indent="${line%%[! ]*}"  # leading spaces

    # Top-level guard name (2-space indent under guards:)
    if [[ ${#indent} -eq 2 ]] && [[ "$trimmed" =~ ^([a-z_]+):$ ]]; then
      current_guard="${BASH_REMATCH[1]}"
      continue
    fi

    # enabled: true/false (4-space indent)
    if [[ -n "$current_guard" ]] && [[ ${#indent} -ge 4 ]] && [[ "$trimmed" =~ ^enabled:[[:space:]]*(true|false) ]]; then
      IRON_DOME_GUARD_ENABLED[$current_guard]="${BASH_REMATCH[1]}"
      continue
    fi

    # Reset guard context on dedent
    if [[ ${#indent} -le 1 ]] && [[ -n "$trimmed" ]] && [[ ! "$trimmed" =~ ^# ]]; then
      current_guard=""
    fi
  done < "$config_file"

  # SEC #2761 — untrusted in-repo config may not disable critical guards.
  # Re-assert them ON and log loudly; only trusted IRON_DOME_HOME config may
  # disable a critical guard.
  if [[ "$config_trusted" != true && "${IRON_DOME_ALLOW_REPO_OVERRIDE:-0}" != "1" ]]; then
    local _cg
    for _cg in "${IRON_DOME_CRITICAL_GUARDS[@]}"; do
      if [[ "${IRON_DOME_GUARD_ENABLED[$_cg]:-true}" == "false" ]]; then
        echo "Iron Dome: SECURITY — in-repo config tried to disable critical guard '$_cg'; ignored (only trusted IRON_DOME_HOME config may)." >&2
        IRON_DOME_GUARD_ENABLED[$_cg]=true
      fi
    done
  fi

  # Load per-repo override (.iron-dome.yml)
  # SEC #2761 — disabled_patterns / additional_patterns are honored ONLY from a
  # trusted config source. The override file lives in the scanned tree, so an
  # attacker could otherwise disable secret patterns by name, or inject a
  # catastrophic-backtracking grep -P regex (ReDoS / denial-of-detection), on
  # the same PR that plants the secret.
  local override_file="${repo_root}/.iron-dome.yml"
  if [[ -f "$override_file" && "$config_trusted" != true && "${IRON_DOME_ALLOW_REPO_OVERRIDE:-0}" != "1" ]]; then
    echo "Iron Dome: SECURITY — ignoring in-repo .iron-dome.yml override (disabled_patterns/additional_patterns) from scanned tree. Set IRON_DOME_ALLOW_REPO_OVERRIDE=1 to opt in (local dev only)." >&2
  elif [[ -f "$override_file" ]]; then
    local in_disabled=false
    while IFS= read -r line; do
      local trimmed="${line#"${line%%[![:space:]]*}"}"
      if [[ "$trimmed" =~ ^disabled_patterns: ]]; then
        in_disabled=true
        continue
      fi
      if $in_disabled; then
        if [[ "$trimmed" =~ ^-[[:space:]]*\"(.+)\" ]] || [[ "$trimmed" =~ ^-[[:space:]]*\'(.+)\' ]]; then
          IRON_DOME_DISABLED_PATTERNS+=("${BASH_REMATCH[1]}")
        elif [[ -n "$trimmed" ]] && ! [[ "$trimmed" =~ ^- ]]; then
          in_disabled=false
        fi
      fi
    done < "$override_file"

    # additional_patterns: append custom named secret patterns (PBI #428)
    local in_additional=false ap_name="" ap_pattern=""
    while IFS= read -r line; do
      line="${line%$'\r'}"
      local atrim="${line#"${line%%[![:space:]]*}"}"
      if [[ "$atrim" =~ ^additional_patterns: ]]; then in_additional=true; continue; fi
      if $in_additional; then
        if [[ "$atrim" =~ ^-[[:space:]]*name:[[:space:]]*(.+) ]]; then
          if [[ -n "$ap_name" ]] && [[ -n "$ap_pattern" ]]; then IRON_DOME_SECRET_PATTERNS+=("${ap_name}|||${ap_pattern}"); fi
          ap_name="$(printf '%s' "${BASH_REMATCH[1]}" | sed -E "s/^[\"']//; s/[\"' ]+\$//")"; ap_pattern=""
        elif [[ "$atrim" =~ ^pattern:[[:space:]]*(.+) ]]; then
          ap_pattern="$(printf '%s' "${BASH_REMATCH[1]}" | sed -E "s/^[\"']//; s/[\"' ]+\$//")"
        elif [[ -n "$atrim" ]] && [[ "$atrim" =~ ^[a-z_]+: ]] && ! [[ "$atrim" =~ ^(name|pattern|severity): ]]; then
          if [[ -n "$ap_name" ]] && [[ -n "$ap_pattern" ]]; then IRON_DOME_SECRET_PATTERNS+=("${ap_name}|||${ap_pattern}"); fi
          ap_name=""; ap_pattern=""; in_additional=false
        fi
      fi
    done < "$override_file"
    if [[ -n "$ap_name" ]] && [[ -n "$ap_pattern" ]]; then IRON_DOME_SECRET_PATTERNS+=("${ap_name}|||${ap_pattern}"); fi
  fi
}

# --- Whitelist (per-file exceptions with mandatory reason) ---
# Format in iron-dome.yml:
#   whitelist:
#     - file: "tests/fixtures/fake-creds.json"
#       guard: sensitive_files
#       reason: "Test fixture, no real credentials"
#
# Parsed as: IRON_DOME_WHITELIST[guard|||file_glob] = reason

declare -A IRON_DOME_WHITELIST

_load_whitelist() {
  local config_file="$1"
  [[ -z "$config_file" ]] && return 0
  [[ ! -f "$config_file" ]] && return 0

  local in_whitelist=false
  local current_file="" current_guard="" current_reason=""

  while IFS= read -r line; do
    line="${line%$'\r'}"
    local trimmed="${line#"${line%%[![:space:]]*}"}"

    if [[ "$trimmed" == "whitelist:"* ]]; then
      in_whitelist=true
      continue
    fi

    if ! $in_whitelist; then continue; fi

    # New section at same or lower indent = end of whitelist
    local indent="${line%%[! ]*}"
    if [[ ${#indent} -eq 0 ]] && [[ -n "$trimmed" ]] && [[ ! "$trimmed" =~ ^# ]] && [[ "$trimmed" != "[]" ]]; then
      # Save last entry
      if [[ -n "$current_file" ]] && [[ -n "$current_guard" ]]; then
        IRON_DOME_WHITELIST["${current_guard}|||${current_file}"]="${current_reason:-no reason}"
      fi
      in_whitelist=false
      continue
    fi

    # New entry starts with "- file:"
    if [[ "$trimmed" =~ ^-[[:space:]]*file:[[:space:]]*\"(.+)\" ]] || [[ "$trimmed" =~ ^-[[:space:]]*file:[[:space:]]*(.+) ]]; then
      # Save previous entry
      if [[ -n "$current_file" ]] && [[ -n "$current_guard" ]]; then
        IRON_DOME_WHITELIST["${current_guard}|||${current_file}"]="${current_reason:-no reason}"
      fi
      current_file="${BASH_REMATCH[1]}"
      current_file="${current_file%\"}"  # strip trailing quote
      current_guard=""
      current_reason=""
      continue
    fi

    if [[ "$trimmed" =~ ^guard:[[:space:]]*(.+) ]]; then
      current_guard="${BASH_REMATCH[1]}"
      current_guard="${current_guard%\"}"
      current_guard="${current_guard#\"}"
      continue
    fi

    if [[ "$trimmed" =~ ^reason:[[:space:]]*\"(.+)\" ]] || [[ "$trimmed" =~ ^reason:[[:space:]]*(.+) ]]; then
      current_reason="${BASH_REMATCH[1]}"
      current_reason="${current_reason%\"}"
      continue
    fi

    if [[ "$trimmed" =~ ^pattern:[[:space:]]*\"(.+)\" ]] || [[ "$trimmed" =~ ^pattern:[[:space:]]*(.+) ]]; then
      # pattern narrows the whitelist to a specific secret pattern name
      # stored as guard|||file|||pattern
      local pat="${BASH_REMATCH[1]}"
      pat="${pat%\"}"
      current_guard="${current_guard}|||${pat}"
      continue
    fi
  done < "$config_file"

  # Save last entry
  if [[ -n "$current_file" ]] && [[ -n "$current_guard" ]]; then
    IRON_DOME_WHITELIST["${current_guard}|||${current_file}"]="${current_reason:-no reason}"
  fi
}

_is_whitelisted() {
  local guard="$1"
  local file="$2"

  # SEC #2761 — an in-repo (untrusted) whitelist may not exempt a critical
  # guard; only a trusted IRON_DOME_HOME config (or explicit local opt-in) can.
  # Closes the "whitelist everything" bypass committed in the scanned tree.
  local _cg
  for _cg in "${IRON_DOME_CRITICAL_GUARDS[@]}"; do
    if [[ "$_cg" == "$guard" ]]; then
      if [[ "${IRON_DOME_CONFIG_TRUSTED:-false}" != true && "${IRON_DOME_ALLOW_REPO_OVERRIDE:-0}" != "1" ]]; then
        return 1
      fi
      break
    fi
  done

  for key in "${!IRON_DOME_WHITELIST[@]}"; do
    local wl_guard="${key%%|||*}"
    local wl_file="${key##*|||}"

    # SEC #2761 — exact guard match only (the old substring match let a
    # whitelist for one guard leak onto another), and reject overly-broad file
    # globs that would whitelist the entire tree.
    [[ "$wl_guard" != "$guard" ]] && continue
    case "$wl_file" in
      ''|'*'|'**'|'*/*'|'**/*'|'.'|'./*') continue ;;
    esac

    # Check file glob match
    if [[ "$file" == $wl_file ]] || [[ "$(basename "$file")" == $wl_file ]]; then
      local reason="${IRON_DOME_WHITELIST[$key]}"
      echo "  WHITELISTED: $file ($guard) — $reason"
      _guard_log "$guard" "whitelisted" "$file: $reason"
      return 0
    fi
  done
  return 1
}

# --- Guard enabled checker ---
_is_guard_enabled() {
  local guard_name="$1"
  local val="${IRON_DOME_GUARD_ENABLED[$guard_name]:-}"

  # Default: secrets, conflict_markers, large_file, sensitive_files, branch_policy = on
  # v2.2.0: added 8 EW-ported guards on by default (mcp_json_duplicate, wi_link,
  #   inline_credentials, exec_bit, env_secrets_source, worktree_discipline,
  #   git_garbage, anti_hardcoded). All have escape hatches via env var.
  # Everything else = off
  if [[ -z "$val" ]]; then
    case "$guard_name" in
      secrets|conflict_markers|large_file|sensitive_files|branch_policy|encoding|path_length) return 0 ;;
      mcp_json_duplicate|wi_link|inline_credentials|exec_bit|env_secrets_source) return 0 ;;
      worktree_discipline|git_garbage|anti_hardcoded|coupling) return 0 ;;
      *) return 1 ;;
    esac
  fi

  [[ "$val" == "true" ]]
}

# --- Load guard modules ---
_load_guards() {
  local guard_dir
  guard_dir="$(_iron_dome_home)/src/guards"

  # Also check if guards are in same dir (installed flat)
  if [[ ! -d "$guard_dir" ]]; then
    guard_dir="$(_iron_dome_home)/guards"
  fi

  if [[ -d "$guard_dir" ]]; then
    for guard_file in "$guard_dir"/*.sh; do
      [[ -f "$guard_file" ]] && source "$guard_file"
    done
  fi

  # Load config after guards (config decides which ones run)
  _load_config

  # Load whitelist from config
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
  if [[ -f "${repo_root}/iron-dome.yml" ]]; then
    _load_whitelist "${repo_root}/iron-dome.yml"
  elif [[ -f "$(_iron_dome_home)/iron-dome.yml" ]]; then
    _load_whitelist "$(_iron_dome_home)/iron-dome.yml"
  fi
}
