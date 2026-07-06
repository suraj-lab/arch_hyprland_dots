#!/usr/bin/env bash
# Bootstrap only the validated Gaming Mode setup from dotfiles.
# This delegates to the main fresh-install bootstrap so package lists,
# CachyOS repo setup, sudoers patching, and root helper deployment stay in one place.
set -euo pipefail

DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$DOT/scripts/bootstrap-arch.sh" \
  --no-desktop \
  --no-daily \
  --no-virt \
  --no-flatpak \
  --no-dotfiles \
  "$@"
