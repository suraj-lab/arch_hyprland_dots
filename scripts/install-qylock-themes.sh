#!/bin/bash
# Install all qylock SDDM themes into /usr/share/sddm/themes/.
# Run from the root of a cloned https://github.com/Darkkal44/qylock repo.
set -euo pipefail

THEMES_SRC="$(pwd)/themes"
SYSTEM_DIR="/usr/share/sddm/themes"

if [ ! -d "$THEMES_SRC" ]; then
    echo "ERROR: themes/ directory not found in $(pwd)" >&2
    echo "Run this script from the root of a cloned qylock repository." >&2
    exit 1
fi

echo "==> Installing qylock themes to $SYSTEM_DIR ..."
sudo mkdir -p "$SYSTEM_DIR"

# Install top-level theme directories (excluding clockwork — handled separately)
for dir in "$THEMES_SRC"/*/; do
    name="$(basename "$dir")"
    if [ "$name" = "clockwork" ]; then
        # clockwork has sub-variants — install them as flat directory names
        for sub in "$dir"/*/; do
            subname="$(basename "$sub")"
            install_name="clockwork-${subname}"
            echo "  -> ${install_name}"
            sudo rm -rf "$SYSTEM_DIR/$install_name"
            sudo cp -r "$sub" "$SYSTEM_DIR/$install_name"
        done
    else
        echo "  -> ${name}"
        sudo rm -rf "$SYSTEM_DIR/$name"
        sudo cp -r "$dir" "$SYSTEM_DIR/$name"
    fi
done

echo "==> Done. Installed themes:"
ls -1 "$SYSTEM_DIR"

echo ""
echo "Rotation service: run 'scripts/install-sddm-rotation.sh' from the Dotfiles repo"
