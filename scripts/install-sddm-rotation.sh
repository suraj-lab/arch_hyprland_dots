#!/bin/bash
# Install the sddm rotation helper script and systemd service.
# Run from the Dotfiles repo root.
set -euo pipefail

echo "==> Installing sddm-rotate-theme script ..."
sudo cp scripts/sddm-rotate-theme /usr/local/bin/sddm-rotate-theme
sudo chmod +x /usr/local/bin/sddm-rotate-theme

echo "==> Installing systemd service ..."
sudo cp scripts/sddm-rotate-theme.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sddm-rotate-theme.service

echo "==> Done. Theme will change on next boot."
echo "    Check status:  systemctl status sddm-rotate-theme"
echo "    Trigger now:   sudo systemctl start sddm-rotate-theme"
