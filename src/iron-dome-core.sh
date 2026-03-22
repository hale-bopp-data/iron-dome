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

IRON_DOME_VERSION="2.0.0"

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
)

IRON_DOME_SAFE_PATTERNS=(
  '\$\{[A-Z_]+\}'
  '\$env:[A-Z_]+'
  'process\.env\.'
  'os\.environ'
  'System\.getenv'
  "env\(\s*[\"']"
  'ChangeMe'
  'placeholder'
  'example'
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
  local type="$1"
  local name="$2"
  local file="$3"
  local line="$4"

  local finding="${type} [${name}] in ${file}:${line}"
  IRON_DOME_FINDINGS+=("$finding")

  case "$type" in
    SECRET)     IRON_DOME_SECRETS_FOUND=$((IRON_DOME_SECRETS_FOUND + 1)) ;;
    CONFLICT*)  IRON_DOME_CONFLICTS_FOUND=$((IRON_DOME_CONFLICTS_FOUND + 1)) ;;
    DOCKER*)    IRON_DOME_DOCKER_FOUND=$((IRON_DOME_DOCKER_FOUND + 1)) ;;
    DEBT|ENCODING|PATH_LENGTH)
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
    if [[ "$size" -gt 524288 ]]; then return 0; fi  # 512KB scan limit
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
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

  if [[ -f "${repo_root}/iron-dome.yml" ]]; then
    config_file="${repo_root}/iron-dome.yml"
  elif [[ -f "$(_iron_dome_home)/iron-dome.yml" ]]; then
    config_file="$(_iron_dome_home)/iron-dome.yml"
  fi

  # Defaults: what's ON if no config file exists
  IRON_DOME_GUARD_ENABLED=(
    [secrets]=true
    [conflict_markers]=true
    [large_file]=true
    [sensitive_files]=true
    [branch_policy]=true
    [docker_run]=false
    [encoding]=false
    [path_length]=false
    [debt]=false
    [semaphore]=false
    [orphan]=false
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

  # Load per-repo override (.iron-dome.yml)
  local override_file="${repo_root}/.iron-dome.yml"
  if [[ -f "$override_file" ]]; then
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

  for key in "${!IRON_DOME_WHITELIST[@]}"; do
    local wl_guard="${key%%|||*}"
    local wl_file="${key##*|||}"

    if [[ "$wl_guard" == "$guard" ]] || [[ "$wl_guard" == *"$guard"* ]]; then
      # Check file glob match
      if [[ "$file" == $wl_file ]] || [[ "$(basename "$file")" == $wl_file ]]; then
        local reason="${IRON_DOME_WHITELIST[$key]}"
        echo "  WHITELISTED: $file ($guard) — $reason"
        _guard_log "$guard" "whitelisted" "$file: $reason"
        return 0
      fi
    fi
  done
  return 1
}

# --- Guard enabled checker ---
_is_guard_enabled() {
  local guard_name="$1"
  local val="${IRON_DOME_GUARD_ENABLED[$guard_name]:-}"

  # Default: secrets, conflict_markers, large_file, sensitive_files, branch_policy = on
  # Everything else = off
  if [[ -z "$val" ]]; then
    case "$guard_name" in
      secrets|conflict_markers|large_file|sensitive_files|branch_policy) return 0 ;;
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
