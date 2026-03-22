#!/usr/bin/env bash
# Iron Dome — Sensitive File Guard
# Blocks commits of files with dangerous filenames.
# Catches .env, private keys, credentials files by NAME (not content).

guard_sensitive_files() {
  local file="$1"
  local basename
  basename=$(basename "$file")

  # Default patterns
  local patterns=(
    ".env"
    ".env.local"
    ".env.production"
    ".env.staging"
  )

  # Filename extension patterns
  local ext_patterns=(
    "*.pem"
    "*.key"
    "*.pfx"
    "*.p12"
    "*.keystore"
  )

  # Prefix patterns
  local prefix_patterns=(
    "id_rsa"
    "id_ed25519"
    "id_ecdsa"
    "id_dsa"
    "credentials"
    "service-account"
  )

  # Allow patterns (whitelisted)
  local allow_patterns=(
    ".env.example"
    ".env.template"
    ".env.sample"
    "*.pem.example"
  )

  # Check allow list first
  for allow in "${allow_patterns[@]}"; do
    if [[ "$basename" == $allow ]] || [[ "$file" == $allow ]]; then
      return 0
    fi
  done

  # Check exact match
  for pat in "${patterns[@]}"; do
    if [[ "$basename" == "$pat" ]]; then
      _report_finding "SENSITIVE_FILE" "Sensitive filename blocked" "$file" "0"
      return 1
    fi
  done

  # Check extension patterns
  for pat in "${ext_patterns[@]}"; do
    if [[ "$basename" == $pat ]]; then
      _report_finding "SENSITIVE_FILE" "Sensitive file extension blocked" "$file" "0"
      return 1
    fi
  done

  # Check prefix patterns
  for pat in "${prefix_patterns[@]}"; do
    if [[ "$basename" == ${pat}* ]]; then
      _report_finding "SENSITIVE_FILE" "Sensitive filename prefix blocked" "$file" "0"
      return 1
    fi
  done

  return 0
}
