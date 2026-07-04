#!/usr/bin/env bash
# Bootstrap the validated Gaming Mode setup from dotfiles.
# For full machine-specific deployment, clone the private project repo:
#   git clone git@github.com:suraj-lab/arch-gaming-optimization.git ~/Projects/arch-gaming-optimization
set -euo pipefail

DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$HOME/Projects/arch-gaming-optimization"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; }

install_pkg_file() {
  local file="$1"
  grep -hvE '^\s*(#|$)' "$file" | paru -S --needed -
}

if command -v paru >/dev/null 2>&1; then
  say "Installing Gaming Mode package set"
  install_pkg_file "$DOT/packages/gaming-mode.txt"
else
  warn "paru not found. Install paru first, then re-run."
  exit 1
fi

say "Installing home Gaming Mode configs from dotfiles"
install -Dm644 "$DOT/.config/environment.d/99-gaming-session.conf" \
  "$HOME/.config/environment.d/99-gaming-session.conf"
install -Dm644 "$DOT/.config/gamescope/scripts/dell.aw3423dwf.lua" \
  "$HOME/.config/gamescope/scripts/dell.aw3423dwf.lua"

if [[ -x "$PROJECT/scripts/apply-phase34.sh" ]]; then
  say "Applying full machine-specific Gaming Mode deployment"
  sudo "$PROJECT/scripts/apply-phase34.sh"
  "$PROJECT/scripts/verify-deck-mode.sh" || true
else
  warn "Private project repo not found at $PROJECT"
  warn "Packages + home configs are installed, but root helpers/session files are not."
  warn "Clone arch-gaming-optimization and run: sudo ./scripts/apply-phase34.sh"
fi
