#!/usr/bin/env bash
# Usage: scripts/check-official.sh packages/desktop-core.txt [...]
# Fails, listing offenders, if any manifest entry is not a package in the official
# Arch repos (core/extra/multilib). Checks availability only: a locally installed
# CachyOS rebuild of an official package is fine. Needs synced pacman databases.
set -euo pipefail
(( $# )) || { echo "usage: $0 MANIFEST..." >&2; exit 2; }
export LC_ALL=C

# A repo missing from pacman.conf (e.g. multilib before bootstrap enables it) must not abort.
official=$(pacman -Sl core extra multilib 2>/dev/null | awk '{print $2}' | sort -u || true)
bad=$(grep -hvE '^\s*(#|$)' "$@" | awk '{print $1}' | sort -u | comm -23 - <(printf '%s\n' "$official"))

if [[ -n "$bad" ]]; then
  echo "Not in core/extra/multilib:" >&2
  printf '  %s\n' $bad >&2
  exit 1
fi
echo "OK: every entry in $* is in core/extra/multilib"
