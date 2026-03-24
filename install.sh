#!/usr/bin/env bash
# ============================================================================
# Iron Dome — Installer
# ============================================================================
# One-liner install:
#   curl -sL https://raw.githubusercontent.com/hale-bopp-data/iron-dome/main/install.sh | bash
#
# Or with wget:
#   wget -qO- https://raw.githubusercontent.com/hale-bopp-data/iron-dome/main/install.sh | bash
#
# Options (env vars):
#   IRON_DOME_DIR   — installation directory (default: ~/.iron-dome)
#   IRON_DOME_REF   — git ref to install (default: main)
#
# The Dumb Guard: non-AI security for AI-assisted development.
# https://github.com/hale-bopp-data/iron-dome
# ============================================================================

set -euo pipefail

INSTALL_DIR="${IRON_DOME_DIR:-$HOME/.iron-dome}"
GIT_REF="${IRON_DOME_REF:-main}"
REPO_URL="https://github.com/hale-bopp-data/iron-dome.git"

# --- Colors (if terminal supports them) ---
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi

info()  { echo -e "${GREEN}[iron-dome]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[iron-dome]${RESET} $*"; }
error() { echo -e "${RED}[iron-dome]${RESET} $*" >&2; }

# --- Pre-flight checks ---
check_deps() {
  local missing=()
  command -v git  &>/dev/null || missing+=("git")
  command -v bash &>/dev/null || missing+=("bash")
  command -v grep &>/dev/null || missing+=("grep")

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required tools: ${missing[*]}"
    error "Install them and try again."
    exit 1
  fi
}

# --- Install ---
install_iron_dome() {
  info "Installing Iron Dome..."
  echo ""

  check_deps

  # Clone or update
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Updating existing installation in $INSTALL_DIR"
    cd "$INSTALL_DIR"
    git fetch origin --quiet
    git checkout "$GIT_REF" --quiet 2>/dev/null || git checkout "origin/$GIT_REF" --quiet
    git pull origin "$GIT_REF" --quiet 2>/dev/null || true
  else
    if [[ -d "$INSTALL_DIR" ]]; then
      warn "Directory $INSTALL_DIR exists but is not a git repo. Backing up..."
      mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%s)"
    fi
    info "Cloning Iron Dome to $INSTALL_DIR"
    git clone --branch "$GIT_REF" --depth 1 "$REPO_URL" "$INSTALL_DIR" --quiet
  fi

  # Make scripts executable
  chmod +x "$INSTALL_DIR/iron-dome"
  chmod +x "$INSTALL_DIR/src/"*.sh 2>/dev/null || true
  chmod +x "$INSTALL_DIR/src/guards/"*.sh 2>/dev/null || true
  chmod +x "$INSTALL_DIR/src/hooks/"* 2>/dev/null || true

  # Create telemetry dir
  mkdir -p "$HOME/.iron-dome" 2>/dev/null || true

  # Detect shell and suggest PATH addition
  local shell_rc=""
  local current_shell
  current_shell=$(basename "${SHELL:-bash}")

  case "$current_shell" in
    zsh)  shell_rc="$HOME/.zshrc" ;;
    bash)
      if [[ -f "$HOME/.bashrc" ]]; then
        shell_rc="$HOME/.bashrc"
      elif [[ -f "$HOME/.bash_profile" ]]; then
        shell_rc="$HOME/.bash_profile"
      fi
      ;;
    fish) shell_rc="$HOME/.config/fish/config.fish" ;;
  esac

  # Check if already in PATH
  local path_line="export PATH=\"$INSTALL_DIR:\$PATH\""
  local in_path=false

  if echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR" 2>/dev/null; then
    in_path=true
  elif [[ -n "$shell_rc" ]] && grep -qF "$INSTALL_DIR" "$shell_rc" 2>/dev/null; then
    in_path=true
  fi

  if ! $in_path && [[ -n "$shell_rc" ]]; then
    echo "" >> "$shell_rc"
    echo "# Iron Dome — The Dumb Guard" >> "$shell_rc"
    echo "$path_line" >> "$shell_rc"
    info "Added Iron Dome to PATH in $shell_rc"
  elif $in_path; then
    info "Iron Dome already in PATH"
  else
    warn "Could not detect shell config. Add this to your shell profile:"
    echo "  $path_line"
  fi

  # Print success
  echo ""
  echo -e "${BOLD}Iron Dome installed successfully.${RESET}"
  echo ""
  echo "  Version:  $(grep 'IRON_DOME_VERSION=' "$INSTALL_DIR/src/iron-dome-core.sh" | head -1 | cut -d'"' -f2)"
  echo "  Location: $INSTALL_DIR"
  echo ""
  echo "  Quick start:"
  echo "    source $shell_rc        # reload PATH (or open a new terminal)"
  echo "    cd your-project"
  echo "    iron-dome init           # install hooks"
  echo "    iron-dome doctor         # verify"
  echo ""
  echo "  Documentation: https://github.com/hale-bopp-data/iron-dome"
  echo ""
}

# --- Uninstall (if called with --uninstall) ---
uninstall_iron_dome() {
  info "Uninstalling Iron Dome..."

  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    info "Removed $INSTALL_DIR"
  else
    warn "Iron Dome not found at $INSTALL_DIR"
  fi

  # Note: does not remove PATH entry from shell rc (manual cleanup)
  warn "You may want to remove the PATH entry from your shell config."
  info "Done."
}

# --- Main ---
case "${1:-install}" in
  install)    install_iron_dome ;;
  --uninstall|uninstall) uninstall_iron_dome ;;
  *)
    echo "Usage: install.sh [install|uninstall]"
    exit 1
    ;;
esac
