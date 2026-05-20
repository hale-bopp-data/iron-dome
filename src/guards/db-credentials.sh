#!/usr/bin/env bash
# Iron Dome Guard: Hardcoded Database Credentials
# Hook: pre-commit
# Default: ON
#
# Detects database connection strings with embedded credentials.
# Covers PostgreSQL, MySQL, MongoDB, SQL Server, Redis with auth.
# Safe alternative: use environment variables for connection strings.

guard_db_credentials() {
  local file="$1"

  if _is_whitelisted "db_credentials" "$file"; then return 0; fi

  # Skip binary/image files
  case "$file" in
    *.png|*.jpg|*.gif|*.ico|*.woff*|*.ttf|*.pdf|*.svg|*.zip|*.gz) return 0 ;;
  esac

  local found=0

  # Pattern 1: protocol://user:password@host URLs
  local p1='(postgresql|postgres|mysql|mongodb(\+srv)?|sqlserver|mssql|redis)://[A-Za-z0-9_]+:[^@\s$}{]+@[^\s"'\'']+'
  local matches
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p1" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    # Skip safe patterns (env refs, examples, placeholders)
    if _is_safe_match "$line_content"; then continue; fi
    # Skip comments
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '^\s*(#|//)' 2>/dev/null; then
      continue
    fi
    local line_num="${match_line%%:*}"
    _report_finding "DB_CRED" "Database URL with embedded credentials" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  # Pattern 2: POSTGRES_PASSWORD / MYSQL_ROOT_PASSWORD with literal value (not env var)
  local p2='(POSTGRES_PASSWORD|MYSQL_ROOT_PASSWORD|MONGO_INITDB_ROOT_PASSWORD|SA_PASSWORD)\s*[:=]\s*["\x27]?[A-Za-z0-9_!@#$%^&*]{6,}'
  matches=$(LC_ALL=en_US.UTF-8 grep -nP -- "$p2" "$file" 2>/dev/null || true)
  while IFS= read -r match_line; do
    [[ -z "$match_line" ]] && continue
    local line_content="${match_line#*:}"
    if _is_safe_match "$line_content"; then continue; fi
    # Skip if value is an env var reference
    if echo "$line_content" | LC_ALL=en_US.UTF-8 grep -qP '\$\{|\$\(' 2>/dev/null; then
      continue
    fi
    local line_num="${match_line%%:*}"
    _report_finding "DB_CRED" "Hardcoded database password in config" "$file" "$line_num"
    found=$((found + 1))
  done <<< "$matches"

  return $found
}
