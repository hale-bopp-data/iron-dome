#!/usr/bin/env bash
# ============================================================================
# Iron Dome Guard: Coupling (if changed A, must change B)
# ============================================================================
# Enforces coupling rules between file paths: if you touch files matching
# glob A, you must also touch files matching glob B.
#
# Config (iron-dome.yml):
#   coupling:
#     enabled: true
#     severity: advisory
#     rules:
#       - if_changed: "src/db/**"
#         must_change: ["docs/**", "CHANGELOG.md"]
#         reason: "DB schema changes require documentation updates"
#
# Trigger: repo-level — runs once per commit, checks all staged files
# Severity: advisory (non-blocking) — configurable
# ============================================================================

# --- Glob-to-regex converter ---
# Converts a glob pattern (with ** and *) to a bash regex for matching
# against staged file paths.
#
# Rules:
#   **  → .* (recursive)
#   *   → [^/]* (within directory, no slash)
#   ?   → [^/]
#   .   → \.
#   everything else → literal
_glob_to_regex() {
  local glob="$1"
  local regex=""
  local i=0
  local len=${#glob}

  while [[ $i -lt $len ]]; do
    local c="${glob:$i:1}"
    if [[ "$c" == "*" ]]; then
      if [[ $((i + 1)) -lt $len ]] && [[ "${glob:$((i + 1)):1}" == "*" ]]; then
        regex="${regex}.*"
        i=$((i + 2))
      else
        regex="${regex}[^/]*"
        i=$((i + 1))
      fi
    elif [[ "$c" == "?" ]]; then
      regex="${regex}[^/]"
      i=$((i + 1))
    elif [[ "$c" == "." ]]; then
      regex="${regex}\\."
      i=$((i + 1))
    else
      regex="${regex}${c}"
      i=$((i + 1))
    fi
  done

  # Anchor: must match a path segment or full path
  echo "^${regex}$"
}

# --- Check if any staged file matches a glob ---
_any_matches() {
  local glob="$1"
  local files="$2"
  local regex
  regex=$(_glob_to_regex "$glob")

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    # Use bash's built-in =~ for portability (no grep -P dependency)
    if [[ "$file" =~ $regex ]]; then
      return 0
    fi
  done <<< "$files"
  return 1
}

# --- Parse coupling rules from iron-dome.yml ---
# Outputs rules as lines: if_changed|must_change1,must_change2|reason
_parse_coupling_rules() {
  local config_file="$1"
  [[ -z "$config_file" ]] && return 0
  [[ ! -f "$config_file" ]] && return 0

  local in_coupling=false
  local in_rules=false
  local current_if=""
  local current_must=()
  local current_reason=""

  while IFS= read -r line; do
    line="${line%$'\r'}"
    local trimmed="${line#"${line%%[![:space:]]*}"}"

    # Enter coupling section
    if [[ "$trimmed" == "coupling:" ]]; then
      in_coupling=true
      continue
    fi

    $in_coupling || continue

    # Exit coupling on dedent to top-level key
    if [[ "${line:0:1}" != " " && "${line:0:1}" != "" ]] && [[ -n "$trimmed" ]] && [[ "$trimmed" != "rules:" ]]; then
      in_coupling=false
      continue
    fi

    # enabled: / severity: — skip
    if [[ "$trimmed" =~ ^(enabled|severity): ]]; then
      continue
    fi

    # Enter rules list
    if [[ "$trimmed" == "rules:" ]]; then
      in_rules=true
      continue
    fi

    $in_rules || continue

    # New rule entry: - if_changed: "..."
    if [[ "$trimmed" =~ ^-[[:space:]]*if_changed:[[:space:]]*\"(.+)\" ]] || [[ "$trimmed" =~ ^-[[:space:]]*if_changed:[[:space:]]*(.+) ]]; then
      # Emit previous rule
      if [[ -n "$current_if" ]]; then
        local must_joined
        must_joined=$(printf '%s,' "${current_must[@]}")
        must_joined="${must_joined%,}"
        echo "${current_if}|${must_joined}|${current_reason}"
      fi
      current_if="${BASH_REMATCH[1]}"
      current_if="${current_if%\"}"
      current_must=()
      current_reason=""
      continue
    fi

    # must_change: [...] or must_change: "single"
    if [[ "$trimmed" =~ ^must_change:[[:space:]]*\[(.*)\] ]]; then
      local items="${BASH_REMATCH[1]}"
      # Split comma-separated quoted items
      while [[ "$items" =~ \"([^\"]+)\" ]]; do
        current_must+=("${BASH_REMATCH[1]}")
        items="${items#*\"}"
        items="${items#*\"}"
        items="${items#*,}"
      done
      continue
    fi

    if [[ "$trimmed" =~ ^must_change:[[:space:]]*\"(.+)\" ]] || [[ "$trimmed" =~ ^must_change:[[:space:]]*(.+) ]]; then
      current_must+=("${BASH_REMATCH[1]}")
      current_must[-1]="${current_must[-1]%\"}"
      continue
    fi

    # reason: "..."
    if [[ "$trimmed" =~ ^reason:[[:space:]]*\"(.+)\" ]] || [[ "$trimmed" =~ ^reason:[[:space:]]*(.+) ]]; then
      current_reason="${BASH_REMATCH[1]}"
      current_reason="${current_reason%\"}"
      continue
    fi
  done < "$config_file"

  # Emit last rule
  if [[ -n "$current_if" ]]; then
    local must_joined
    must_joined=$(printf '%s,' "${current_must[@]}")
    must_joined="${must_joined%,}"
    echo "${current_if}|${must_joined}|${current_reason}"
  fi
}

# --- Main coupling guard ---
guard_coupling() {
  local staged_files="$1"

  # Find iron-dome.yml
  local config_file=""
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
  if [[ -f "${repo_root}/iron-dome.yml" ]]; then
    config_file="${repo_root}/iron-dome.yml"
  elif [[ -n "${IRON_DOME_HOME:-}" ]] && [[ -f "${IRON_DOME_HOME}/iron-dome.yml" ]]; then
    config_file="${IRON_DOME_HOME}/iron-dome.yml"
  fi

  [[ -z "$config_file" ]] && return 0

  local errors=0

  while IFS='|' read -r if_changed must_joined reason; do
    [[ -z "$if_changed" ]] && continue

    # Check if any staged file matches if_changed
    if ! _any_matches "$if_changed" "$staged_files"; then
      continue
    fi

    # Split must_change list
    IFS=',' read -ra must_list <<< "$must_joined"

    for must_glob in "${must_list[@]}"; do
      [[ -z "$must_glob" ]] && continue

      if ! _any_matches "$must_glob" "$staged_files"; then
        echo "  COUPLING: Changed '$if_changed' but '$must_glob' not changed"
        [[ -n "$reason" ]] && echo "  REASON:  $reason"
        echo "  FIX:     Also update files matching '$must_glob' or add to whitelist"
        errors=$((errors + 1))
      fi
    done
  done < <(_parse_coupling_rules "$config_file")

  if [[ $errors -gt 0 ]]; then
    _report_finding "COUPLING" "${errors} coupling violation(s)" "" "0"
    return 1
  fi

  return 0
}
