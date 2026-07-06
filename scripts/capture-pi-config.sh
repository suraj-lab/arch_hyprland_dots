#!/usr/bin/env bash
# Capture the safe parts of ~/.pi/agent into the repo's pi/ directory.
# Excludes auth.json, caches, sessions, logs, and installed packages.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HOME/.pi/agent"
DST="$REPO_DIR/pi"

mkdir -p "$DST"
cp -f "$SRC/AGENTS.md" "$SRC/SYSTEM.md" "$SRC/settings.json" \
      "$SRC/models.json" "$SRC/mcp.json" "$DST/"
rsync -a --delete "$SRC/skills/" "$DST/skills/"
rsync -a --delete "$SRC/prompts/" "$DST/prompts/"
rsync -a --delete "$SRC/themes/" "$DST/themes/"

# Never ship credentials.
if grep -rlE '"(sk-[A-Za-z0-9]|ant-api|ghp_)' "$DST" >/dev/null 2>&1; then
    echo "ERROR: possible credential found in captured pi config; aborting." >&2
    exit 1
fi
echo "pi config captured to $DST"
