# Package manifests

These manifests are consumed by `scripts/bootstrap-arch.sh`.

- `desktop-core.txt` — Hyprland/Quickshell desktop baseline.
- `daily-apps.txt` — curated daily workstation apps and utilities.
- `gaming-mode.txt` — validated SteamOS-style Gaming Mode package set (GPU drivers live in `gpu-*.txt`).
- `gpu-amd.txt` / `gpu-nvidia.txt` / `gpu-intel.txt` — GPU driver sets; the bootstrap auto-detects via `lspci` (`--gpu` overrides).
- `laptop.txt` — laptop extras (power-profiles-daemon, brightnessctl); opt-in via `--laptop`.
- `virtualization.txt` — local VM / passthrough stack; opt-in via `--virt`.
- `flatpak-apps.txt` — Flatpak app IDs installed from Flathub.
- `current-explicit.txt` — captured `pacman -Qqen` reference from the current machine.
- `current-aur.txt` — captured `pacman -Qqem` reference from the current machine.

After editing `desktop-core.txt`, run `scripts/sync-readme-pkglist.sh` to regenerate the backup one-shot list in the root README.

The curated files are the default install path. The captured current-state files are intentionally optional via `--full-current` because they include hardware/workflow-specific packages and may change over time.
