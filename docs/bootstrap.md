# Fresh Arch bootstrap

Goal: start from a barebones Arch install produced by `archinstall`, run one script, reboot, and land in the same Hyprland/Quickshell + Gaming Mode workstation, including SDDM theming and the pi.dev coding agent.

Default profile: desktop-core + daily apps + Gaming Mode + Flatpaks + dotfiles + SDDM themes/rotation + pi.dev. Virtualization is opt-in via `--virt`.

## The full flow

1. Boot the Arch ISO, connect to the network (`iwctl` for Wi-Fi, ethernet just works).
2. Run `archinstall` pre-seeded from this repo — it asks only for **disk** and **user/passwords**, everything else is pre-answered:

   ```bash
   archinstall --config-url https://da.gd/surajarch
   ```

   (`https://da.gd/surajarch` is a permanent redirect to
   `https://raw.githubusercontent.com/suraj-lab/arch_hyprland_dots/master/deploy/archinstall.json` —
   use the long form if the shortener is ever unreachable.)

   For the disk menu: choose *best-effort default layout* → your target disk → **btrfs** → default subvolume structure → compression. Passwords are never stored in the repo by design.

   `deploy/archinstall.json` was written against the archinstall 2.8.6 schema; if a newer ISO rejects it, fall back to answering the menus manually with the table below.
3. Reboot into the fresh install, log in as your user on a TTY.
4. Clone this repo and run the bootstrap:

   ```bash
   sudo pacman -S --needed git
   mkdir -p ~/Projects/Dotfiles
   git clone <this-repo-url> ~/Projects/Dotfiles/arch_hyprland_dots
   cd ~/Projects/Dotfiles/arch_hyprland_dots
   ./scripts/bootstrap-arch.sh --yes
   reboot
   ```

5. Log into Hyprland via SDDM. Run `pi` once to log in (auth is per-machine).
6. Re-add data disks to fstab (see "Multiple disks" below).

## archinstall choices

| Section | Choice |
|---|---|
| Mirrors | your region |
| Disk configuration | **the target disk only** — best-effort default partition layout, **btrfs** with default subvolume structure (`@`, `@home`, `@log`, `@pkg`, `@.snapshots`) and compression. This matches the current machine. |
| Disk encryption | none (current machine is unencrypted) |
| Bootloader | **systemd-boot** |
| Swap | **zram** (enabled) |
| Hostname / root password | as you like |
| User account | create your login user, **superuser (sudo) = yes** |
| Profile | **Minimal** — the bootstrap installs the whole desktop itself |
| Audio | **PipeWire** |
| Kernel | `linux` (CachyOS repos are added later by the script; add `linux-cachyos` afterwards if wanted) |
| Network configuration | **NetworkManager** |
| Additional packages | none needed (`git` helps) |
| Timezone / NTP | your region, NTP on |

## Multiple disks

`archinstall` only partitions the disk you explicitly select in "Disk configuration" — every other disk is left alone. The risk is picking the wrong one, and NVMe numbering (`nvme0`, `nvme1`, …) is **not stable across boots or reinstalls**.

Before selecting a disk, identify it from a live shell:

```bash
lsblk -f -o NAME,FSTYPE,LABEL,SIZE,MODEL
```

Pick by **size + model + existing filesystem**, never by remembered device name. On the current machine the OS target is the 931.5G NVMe carrying btrfs + a 1G vfat `/boot`; the disks that must never be selected are the macOS disk (apfs), the SteamOS-style A/B disk (multiple small esp/rootfs partitions), the NTFS games disk, and the ext4 `second` data drive. If in doubt, physically unplug everything except the target.

After the first boot, re-add data disks by **label** with `nofail` so a missing disk never blocks boot:

```bash
lsblk -f                      # verify identity first
sudo mkdir -p /mnt/second
echo 'LABEL=second /mnt/second auto nosuid,nodev,nofail,x-gvfs-show 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
```

NTFS disks additionally need `ntfs-3g` (installed by the daily-apps manifest).

## Is the script interactive?

Yes, when you want it to be:

- **No arguments on a terminal** (or `--interactive`/`-i`): a linutil-style component menu — toggle desktop/daily/gaming/SDDM themes/flatpak/dotfiles/pi/virt/laptop/full-snapshot/CachyOS/multilib by number, Enter to continue. If Gaming Mode is selected it then auto-detects GPUs (`lspci`) and connected outputs (`/sys/class/drm`) and lets you pick, plus a GPU driver-set prompt (amd/nvidia/intel/none). Ends with the plan summary and one `Continue? [y/N]`.
- **With flags**: fully scripted; the menu is skipped and flags decide everything. Still shows the plan + one confirm.
- With `--yes`: no prompts at all — pacman/paru/flatpak run `--noconfirm`. The only interaction left is the **sudo password** early on.
- With `--dry-run`: prints every command it would run, touches nothing.

Everything it replaces is backed up under `~/.local/state/suraj-bootstrap/backups/<timestamp>/`.

## What gets installed

Package manifests live in `packages/` (one name per line, `#` comments):

- **desktop-core.txt** — Hyprland, hyprlock, quickshell-git, SDDM (+tokyo-night theme), PipeWire/WirePlumber stack, xdg-desktop-portal-hyprland, polkit agent, ghostty, starship, firefox, thunar, clipboard/screenshot tooling (wl-clipboard, cliphist, grim/slurp/grimblast, hyprpicker), wallpapers/theming (awww, matugen, nwg-look/displays, nordic-theme, papirus), fonts (noto, JetBrains Mono Nerd), networkmanager, btop, fastfetch.
- **daily-apps.txt** — shells/editors/dev (zsh, neovim, vim, vscodium, github-cli, go, php, python-pip, qmk, fd, tree), terminals/monitoring (kitty, htop, nvtop, dysk), browsers/comms/media (brave, webcord, spotify, vlc, obs-studio, libreoffice, localsend, zoom, icaclient, lmstudio), files/disks/network (file-roller, gnome-disk-utility, gvfs stack, udiskie, samba, freerdp, tigervnc, wireshark, gufw), printing/scanning (cups, hplip, simple-scan, sane), hardware/RGB/fans (openrgb, lact, fancontrol-gui, lianli-linux-git, ddcutil, fwupd, smartmontools), archives/Hackintosh utilities (7zip, testdisk, dmg2img, hfsprogs, uefitool, acpica).
- **gaming-mode.txt** — gamescope + gamescope-session-cachyos, jupiter-hw-support, steam, proton-cachyos, gamemode, mangohud/goverlay, lutris, protontricks/protonup-qt, vulkan-radeon (+lib32s), python-evdev, udisks2.
- **gpu-amd.txt / gpu-nvidia.txt / gpu-intel.txt** — auto-selected via `lspci` (override with `--gpu`). AMD uses RADV (`vulkan-radeon`), the driver Valve targets for Proton — with CachyOS repos enabled, mesa/vulkan/gamescope automatically resolve to CachyOS-optimized builds. NVIDIA uses `nvidia-open-dkms` (NVIDIA's recommended default for Turing/GTX 16xx+; older cards: swap to `nvidia-dkms`). Note: the Gaming Mode gamescope session is validated on AMD only — on NVIDIA expect desktop Steam to work but the SteamOS-style session may need fiddling.
- **laptop.txt** (opt-in `--laptop`) — power-profiles-daemon, brightnessctl.
- **flatpak-apps.txt** — Flatseal, Bottles.
- **virtualization.txt** (opt-in `--virt`) — qemu-full, virt-manager, looking-glass, OVMF, swtpm, passthrough tooling.
- **current-explicit.txt / current-aur.txt** — full machine snapshots, installed only with `--full-current`.

## What the script changes

- enables `[multilib]` when missing
- optionally enables CachyOS repos for the current Gaming Mode stack
- installs `paru`
- installs package manifests from `packages/`
- adds Flathub and installs `packages/flatpak-apps.txt`
- copies selected dotfiles into `$HOME`, backing up existing files under `~/.local/state/suraj-bootstrap/backups/`
- deploys Gaming Mode root helpers from `deploy/gaming/`
- installs a scoped sudoers rule for `/usr/local/bin/gaming-session-switch`
- clones the qylock SDDM theme pack and installs the boot-time random theme rotation service
- installs Node.js, the pi.dev coding agent (`@earendil-works/pi-coding-agent` + `context-mode`) into `~/.npm-global`, and copies the captured pi config from `pi/` into `~/.pi/agent/` (auth is per-machine: run `pi` once and log in)
- enables SDDM, NetworkManager, Bluetooth, CUPS, and (with `--virt`) libvirt services

## Hardware overrides

Gaming Mode defaults target the current machine. Override when hardware changes:

```bash
./scripts/bootstrap-arch.sh \
  --gaming-gpu-pci 0000:03:00.0 \
  --gaming-output DP-2 \
  --gaming-aux-output HDMI-A-1 \
  --gaming-vk-device 1002:7550
```

## Keeping the repo in sync

- `./scripts/capture-pi-config.sh` — re-capture `~/.pi/agent` (AGENTS.md, settings, models, skills, prompts, themes; never auth.json) into `pi/`
- `pacman -Qqen > packages/current-explicit.txt` / `pacman -Qqem > packages/current-aur.txt` — refresh package snapshots

## Next generalization steps

- add post-reboot verification (`gaming`, `audio`, `portals`, `flatpak`, `services`)
- support non-CachyOS Arch by swapping Gaming Mode backend choices
