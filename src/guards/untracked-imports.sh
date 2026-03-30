#!/usr/bin/env bash
# ============================================================================
# Iron Dome Guard: Untracked Imports (G-CI-5)
# ============================================================================
# Detects staged TypeScript/JavaScript files that import from relative paths
# pointing to files not tracked by git. These build locally but fail in CI.
#
# Lightweight check: no tsc invocation, pure grep + git status.
# Trigger: staged .ts/.js files with relative imports
# Severity: BLOCKING
# ============================================================================

guard_untracked_imports() {
  local file="$1"

  # Only check TypeScript and JavaScript source files
  case "$file" in
    *.ts|*.tsx|*.js|*.jsx|*.mts|*.mjs) ;;
    *) return 0 ;;
  esac

  # Whitelist check
  if type _is_whitelisted &>/dev/null && _is_whitelisted "untracked_imports" "$file"; then
    return 0
  fi

  local found=0
  local file_dir
  file_dir=$(dirname "$file")

  # Extract relative imports: import ... from './foo' or require('./foo')
  local imports
  imports=$(grep -noP "(?:from|require\()\s*['\"](\.[^'\"]+)['\"]" "$file" 2>/dev/null || true)

  while IFS= read -r import_line; do
    [[ -z "$import_line" ]] && continue

    local line_num="${import_line%%:*}"
    local rest="${import_line#*:}"

    # Extract the path from the match
    local import_path
    import_path=$(echo "$rest" | grep -oP "['\"](\.[^'\"]+)['\"]" | tr -d "'" | tr -d '"' | head -1)
    [[ -z "$import_path" ]] && continue

    # Resolve to actual file path (try common extensions)
    local resolved=""
    for ext in "" ".ts" ".tsx" ".js" ".jsx" ".mts" ".mjs" "/index.ts" "/index.js"; do
      local candidate="${file_dir}/${import_path}${ext}"
      # Normalize path (remove ./ and resolve ..)
      candidate=$(realpath -m "$candidate" 2>/dev/null || echo "$candidate")
      # Make relative to repo root
      local repo_root
      repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
      candidate="${candidate#${repo_root}/}"

      if [[ -f "$candidate" ]]; then
        resolved="$candidate"
        break
      fi
    done

    # If resolved file exists but is not tracked by git = problem
    if [[ -n "$resolved" ]] && [[ -f "$resolved" ]]; then
      if ! git ls-files --error-unmatch "$resolved" &>/dev/null; then
        _report_finding "UNTRACKED_IMPORT" "imports untracked file: $import_path → $resolved" "$file" "$line_num"
        found=$((found + 1))
      fi
    fi
  done <<< "$imports"

  if [[ $found -gt 0 ]]; then
    echo "  FIX: git add <untracked-file> (commit the imported file)"
    return 1
  fi

  return 0
}
