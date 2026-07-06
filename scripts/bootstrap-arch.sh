#!/usr/bin/env bash
# Fresh Arch/CachyOS workstation bootstrap for Suraj's Hyprland dotfiles.
# Intended flow after archinstall + first login:
#   git clone <this repo> ~/Projects/Dotfiles/arch_hyprland_dots
#   cd ~/Projects/Dotfiles/arch_hyprland_dots
#   ./scripts/bootstrap-arch.sh --yes
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_USER="${SUDO_USER:-${USER}}"
TARGET_HOME=""
AUR_HELPER="paru"
AUTO_YES=0
DRY_RUN=0
INTERACTIVE=0
INSTALL_DESKTOP=1
INSTALL_DAILY=1
INSTALL_GAMING=1
INSTALL_VIRT=0
INSTALL_FLATPAK=1
INSTALL_DOTFILES=1
INSTALL_PI=1
INSTALL_SDDM_THEMES=1
INSTALL_LAPTOP=0
INSTALL_FULL_CURRENT=0
GPU_KIND="auto"
ENABLE_CACHYOS=1
ENABLE_MULTILIB=1

# Current-machine defaults. Override with flags when hardware changes.
GAMING_GPU_PCI="0000:03:00.0"
GAMING_OUTPUT="DP-2"
GAMING_AUX_OUTPUT="HDMI-A-1"
GAMING_VK_DEVICE="1002:7550"

usage() {
  cat <<USAGE
Usage: $0 [options]

Profiles default to Suraj's current workstation: desktop + daily apps + gaming + SDDM themes + pi.dev.

Run with no arguments on a terminal to get the interactive component menu.

Options:
  --interactive, -i             force the interactive component menu + hardware detection
  --yes                         non-interactive package/service operations where supported
  --dry-run                     print commands without executing them
  --user NAME                   target login user (default: SUDO_USER or USER)
  --minimal                     only bootstrap paru + desktop-core + dotfiles
  --full-current                also install captured packages/current-explicit.txt + current-aur.txt
  --no-cachyos                  do not add CachyOS repos
  --no-multilib                 do not ensure [multilib]
  --no-desktop                  skip packages/desktop-core.txt
  --no-daily                    skip packages/daily-apps.txt
  --no-gaming                   skip packages/gaming-mode.txt and Gaming Mode deployment
  --virt                        also install packages/virtualization.txt + libvirt setup (off by default)
  --no-flatpak                  skip packages/flatpak-apps.txt
  --no-dotfiles                 skip copying home dotfiles
  --no-pi                       skip pi.dev coding agent install + config
  --no-sddm-themes              skip qylock SDDM themes + boot-time theme rotation
  --laptop                      also install packages/laptop.txt + power-profiles-daemon
  --gpu KIND                    GPU driver set: auto|amd|nvidia|intel|none (default: auto-detect)
  --gaming-gpu-pci PCI          default: $GAMING_GPU_PCI
  --gaming-output CONNECTOR     default: $GAMING_OUTPUT
  --gaming-aux-output CONNECTOR default: $GAMING_AUX_OUTPUT
  --gaming-vk-device VENDOR:ID  default: $GAMING_VK_DEVICE
  -h, --help                    show this help
USAGE
}

ARG_COUNT=$#
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive|-i) INTERACTIVE=1 ;;
    --yes|-y) AUTO_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --user) TARGET_USER="${2:?missing user}"; shift ;;
    --minimal) INSTALL_DAILY=0; INSTALL_GAMING=0; INSTALL_VIRT=0; INSTALL_FLATPAK=0; INSTALL_PI=0; INSTALL_SDDM_THEMES=0; ENABLE_CACHYOS=0 ;;
    --full-current) INSTALL_FULL_CURRENT=1 ;;
    --no-cachyos) ENABLE_CACHYOS=0 ;;
    --no-multilib) ENABLE_MULTILIB=0 ;;
    --no-desktop) INSTALL_DESKTOP=0 ;;
    --no-daily) INSTALL_DAILY=0 ;;
    --no-gaming) INSTALL_GAMING=0 ;;
    --virt) INSTALL_VIRT=1 ;;
    --no-virt) INSTALL_VIRT=0 ;;
    --no-flatpak) INSTALL_FLATPAK=0 ;;
    --no-dotfiles) INSTALL_DOTFILES=0 ;;
    --no-pi) INSTALL_PI=0 ;;
    --no-sddm-themes) INSTALL_SDDM_THEMES=0 ;;
    --laptop) INSTALL_LAPTOP=1 ;;
    --gpu) GPU_KIND="${2:?missing gpu kind}"; shift ;;
    --gaming-gpu-pci) GAMING_GPU_PCI="${2:?missing PCI address}"; shift ;;
    --gaming-output) GAMING_OUTPUT="${2:?missing connector}"; shift ;;
    --gaming-aux-output) GAMING_AUX_OUTPUT="${2:?missing connector}"; shift ;;
    --gaming-vk-device) GAMING_VK_DEVICE="${2:?missing vendor:device}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m  [OK]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m  [WARN]\033[0m %s\n' "$1"; }
run()  { if (( DRY_RUN )); then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
sudo_run() { if (( EUID == 0 )); then run "$@"; else run sudo "$@"; fi; }

if [[ ! -r /etc/arch-release ]]; then
  echo "This bootstrap is for Arch/CachyOS systems." >&2
  exit 1
fi
if (( EUID != 0 )) && ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required when running as a non-root user." >&2
  exit 1
fi
if (( EUID == 0 )) && [[ "$TARGET_USER" == "root" ]]; then
  echo "Refusing to install user dotfiles for root. Run as your login user or pass --user <name>." >&2
  exit 1
fi
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "Target user does not exist: $TARGET_USER" >&2
  exit 1
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"
BACKUP_ROOT="$TARGET_HOME/.local/state/suraj-bootstrap/backups/$(date +%Y%m%d-%H%M%S)"
PACMAN_CONFIRM=()
PARU_CONFIRM=()
MAKEPKG_CONFIRM=""
FLATPAK_CONFIRM=()
apply_auto_yes() {
  AUTO_YES=1
  PACMAN_CONFIRM=(--noconfirm)
  PARU_CONFIRM=(--noconfirm)
  MAKEPKG_CONFIRM="--noconfirm"
  FLATPAK_CONFIRM=(-y)
}
if (( AUTO_YES )); then apply_auto_yes; fi

# Ask for sudo once, then keep the timestamp alive for the whole run
# (AUR builds outlast the default 15-minute sudo cache).
sudo_keepalive() {
  (( DRY_RUN )) && return 0
  (( EUID == 0 )) && return 0
  sudo -v
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

as_user() {
  if [[ "$(id -u)" == "$TARGET_UID" ]]; then
    HOME="$TARGET_HOME" run "$@"
  else
    run sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" "$@"
  fi
}

detect_gpu_kind() {
  # Match PCI vendor IDs, not names: 'ati' is a substring of 'compATIble',
  # which made QXL VMs (and would make Intel iGPUs) detect as amd.
  local pci
  pci="$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
  if grep -q '\[10de:' <<<"$pci"; then echo nvidia
  elif grep -q '\[1002:' <<<"$pci"; then echo amd
  elif grep -q '\[8086:' <<<"$pci"; then echo intel
  else echo none; fi
}

resolve_gpu_kind() {
  if [[ "$GPU_KIND" == auto ]]; then
    GPU_KIND="$(detect_gpu_kind)"
    [[ "$GPU_KIND" == none ]] && warn "No GPU detected via lspci; skipping GPU driver manifest"
  fi
  case "$GPU_KIND" in
    amd|nvidia|intel|none) ;;
    *) echo "Invalid --gpu kind: $GPU_KIND (want auto|amd|nvidia|intel|none)" >&2; exit 2 ;;
  esac
}

detect_gaming_hardware() {
  say "Gaming Mode hardware detection (Enter keeps the shown default)"
  local -a gpus=() outs=()
  local ans line s i
  mapfile -t gpus < <(lspci -nnD 2>/dev/null | grep -Ei 'vga|3d|display' || true)
  if (( ${#gpus[@]} )); then
    echo "Detected GPUs:"
    for i in "${!gpus[@]}"; do printf '    %d) %s\n' "$((i+1))" "${gpus[$i]}"; done
    read -rp "  Gaming GPU [${GAMING_GPU_PCI}]: " ans
    if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#gpus[@]} )); then
      line="${gpus[$((ans-1))]}"
      GAMING_GPU_PCI="${line%% *}"
      [[ "$line" =~ \[([0-9a-f]{4}:[0-9a-f]{4})\][^[]*$ ]] && GAMING_VK_DEVICE="${BASH_REMATCH[1]}"
    fi
  else
    warn "lspci found no GPUs; keeping defaults"
  fi
  for s in /sys/class/drm/card*-*/status; do
    [[ -r "$s" && "$(<"$s")" == connected ]] || continue
    s="${s%/status}"; s="${s##*/}"; outs+=("${s#card*-}")
  done
  if (( ${#outs[@]} )); then
    echo "Connected outputs:"
    for i in "${!outs[@]}"; do printf '    %d) %s\n' "$((i+1))" "${outs[$i]}"; done
    read -rp "  Gaming output [${GAMING_OUTPUT}]: " ans
    [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#outs[@]} )) && GAMING_OUTPUT="${outs[$((ans-1))]}"
    read -rp "  Aux output to force off in Gaming Mode [${GAMING_AUX_OUTPUT}]: " ans
    [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#outs[@]} )) && GAMING_AUX_OUTPUT="${outs[$((ans-1))]}"
  else
    warn "No connected DRM outputs found; keeping defaults"
  fi
  ok "Gaming hardware: GPU=$GAMING_GPU_PCI vk=$GAMING_VK_DEVICE output=$GAMING_OUTPUT aux-off=$GAMING_AUX_OUTPUT"
}

interactive_menu() {
  local -a keys=(INSTALL_DESKTOP INSTALL_DAILY INSTALL_GAMING INSTALL_SDDM_THEMES
                 INSTALL_FLATPAK INSTALL_DOTFILES INSTALL_PI INSTALL_VIRT
                 INSTALL_LAPTOP INSTALL_FULL_CURRENT ENABLE_CACHYOS ENABLE_MULTILIB)
  local -a labels=(
    "Desktop core (Hyprland, Quickshell, SDDM, PipeWire)"
    "Daily apps (browsers, editors, media, hardware tools)"
    "Gaming Mode (Steam, gamescope session + helpers)"
    "SDDM themes + boot-time rotation"
    "Flatpak apps (Flatseal, Bottles)"
    "Copy dotfiles into home"
    "pi.dev coding agent + config"
    "Virtualization (qemu, libvirt, looking-glass)"
    "Laptop extras (power-profiles-daemon, brightnessctl)"
    "Full current-machine package snapshot"
    "CachyOS repos (needed for Gaming Mode session)"
    "pacman [multilib] (needed for Steam)"
  )
  local ans i state
  while true; do
    say "Select components — number toggles, Enter continues, q quits"
    for i in "${!keys[@]}"; do
      state="${!keys[$i]}"
      printf '   %2d) [%s] %s\n' "$((i+1))" "$([[ $state == 1 ]] && echo x || echo ' ')" "${labels[$i]}"
    done
    read -rp "> " ans
    case "$ans" in
      "") break ;;
      q|Q) echo "Aborted."; exit 1 ;;
      *)
        if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#keys[@]} )); then
          printf -v "${keys[$((ans-1))]}" '%d' "$(( ! ${!keys[$((ans-1))]} ))"
        else
          echo "  ? $ans"
        fi ;;
    esac
  done
  local ans2
  if [[ "$GPU_KIND" == auto ]]; then GPU_KIND="$(detect_gpu_kind)"; fi
  read -rp "GPU drivers [Enter = ${GPU_KIND} (detected), or amd/nvidia/intel/none]: " ans2
  if [[ -n "$ans2" ]]; then GPU_KIND="$ans2"; fi
  # if-form, not '&&': a skipped step must not become the function's exit status (set -e)
  if (( INSTALL_GAMING )); then detect_gaming_hardware; fi
}

confirm_plan() {
  say "Bootstrap plan"
  cat <<PLAN
Target user:        $TARGET_USER ($TARGET_HOME)
Dotfiles repo:      $DOTFILES_DIR
CachyOS repos:      $ENABLE_CACHYOS
Multilib:           $ENABLE_MULTILIB
Desktop packages:   $INSTALL_DESKTOP
Daily apps:         $INSTALL_DAILY
Gaming Mode:        $INSTALL_GAMING
Virtualization:     $INSTALL_VIRT
Laptop extras:      $INSTALL_LAPTOP
GPU driver set:     $GPU_KIND
Flatpaks:           $INSTALL_FLATPAK
Copy dotfiles:      $INSTALL_DOTFILES
pi.dev agent:       $INSTALL_PI
SDDM themes:        $INSTALL_SDDM_THEMES
Full current list:  $INSTALL_FULL_CURRENT
Gaming hardware:    GPU=$GAMING_GPU_PCI output=$GAMING_OUTPUT aux=$GAMING_AUX_OUTPUT vk=$GAMING_VK_DEVICE
Backups:            $BACKUP_ROOT
PLAN
  if (( AUTO_YES || DRY_RUN )); then
    return 0
  fi
  read -rp "Continue? (runs unattended from here) [y/N] " ans
  [[ "${ans,,}" == y || "${ans,,}" == yes ]] || exit 1
  # This confirmation IS the consent: no further per-package prompts.
  apply_auto_yes
}

pkg_lines() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] || { warn "Missing package manifest: $f"; continue; }
    grep -hvE '^\s*(#|$)' "$f"
  done | awk '!seen[$0]++'
}

backup_path() {
  local path="$1" rel
  [[ -e "$path" || -L "$path" ]] || return 0
  rel="${path#/}"
  sudo_run install -d -m 0755 "$(dirname "$BACKUP_ROOT/root/$rel")"
  sudo_run cp -a "$path" "$BACKUP_ROOT/root/$rel"
}

backup_home_path() {
  local path="$1" rel
  [[ -e "$path" || -L "$path" ]] || return 0
  rel="${path#"$TARGET_HOME"/}"
  sudo_run install -d -o "$TARGET_UID" -g "$TARGET_GID" "$(dirname "$BACKUP_ROOT/home/$rel")"
  sudo_run cp -a "$path" "$BACKUP_ROOT/home/$rel"
  sudo_run chown -R "$TARGET_UID:$TARGET_GID" "$BACKUP_ROOT/home"
}

ensure_multilib() {
  (( ENABLE_MULTILIB )) || return 0
  say "Ensuring pacman [multilib] is enabled"
  if grep -Eq '^\s*\[multilib\]' /etc/pacman.conf; then
    ok "multilib already active"
    return 0
  fi
  backup_path /etc/pacman.conf
  if (( DRY_RUN )); then
    echo '[dry-run] append managed [multilib] block to /etc/pacman.conf'
  else
    printf '\n# Enabled by Suraj bootstrap\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
  fi
  sudo_run pacman -Sy "${PACMAN_CONFIRM[@]}"
  ok "multilib enabled"
}

ensure_cachyos() {
  (( ENABLE_CACHYOS )) || return 0
  say "Ensuring CachyOS repositories are enabled"
  if grep -Eq '^\s*\[cachyos' /etc/pacman.conf; then
    ok "CachyOS repos already present"
    return 0
  fi
  sudo_run pacman -S --needed "${PACMAN_CONFIRM[@]}" curl ca-certificates
  backup_path /etc/pacman.conf
  local tmp
  tmp="$(mktemp -d)"
  run curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o "$tmp/cachyos-repo.tar.xz"
  run tar xf "$tmp/cachyos-repo.tar.xz" -C "$tmp"
  sudo_run bash "$tmp/cachyos-repo/cachyos-repo.sh" --install
  sudo_run pacman -Sy "${PACMAN_CONFIRM[@]}"
  run rm -rf "$tmp"
  ok "CachyOS repos enabled"
}

ensure_home_dirs() {
  # GNU 'install -d -o USER' creates missing PARENT directories as root when
  # run under sudo. On a fresh home that left ~/.cache root-owned and broke
  # paru with 'Permission denied (os error 13)'. Create + own every level
  # explicitly; also repairs damage from earlier runs.
  local d
  for d in .cache .config .local .local/state; do
    sudo_run mkdir -p "$TARGET_HOME/$d"
    sudo_run chown "$TARGET_UID:$TARGET_GID" "$TARGET_HOME/$d"
  done
}

ensure_paru() {
  say "Ensuring base-devel, git, and paru"
  sudo_run pacman -S --needed "${PACMAN_CONFIRM[@]}" base-devel git curl
  if command -v "$AUR_HELPER" >/dev/null 2>&1; then
    ok "$AUR_HELPER already installed"
    return 0
  fi
  local build_root="$TARGET_HOME/.cache/suraj-bootstrap"
  sudo_run install -d -o "$TARGET_UID" -g "$TARGET_GID" "$build_root"
  as_user rm -rf "$build_root/paru"
  as_user git clone https://aur.archlinux.org/paru.git "$build_root/paru"
  as_user bash -lc "cd '$build_root/paru' && makepkg -si --needed $MAKEPKG_CONFIRM"
  ok "paru installed"
}

install_packages() {
  local files=("$@") pkgs=() missing=() keep=() p m
  mapfile -t pkgs < <(pkg_lines "${files[@]}")
  (( ${#pkgs[@]} )) || return 0
  # Skip packages that no longer exist anywhere (repo/AUR rot) instead of
  # letting one dead entry abort the whole bootstrap.
  mapfile -t missing < <(as_user "$AUR_HELPER" -Si "${pkgs[@]}" 2>&1 >/dev/null | sed -n "s/.*package '\([^']*\)' was not found.*/\1/p" | sort -u)
  if (( ${#missing[@]} )); then
    warn "Unavailable packages skipped (fix the manifest): ${missing[*]}"
    for p in "${pkgs[@]}"; do
      for m in "${missing[@]}"; do [[ "$p" == "$m" ]] && continue 2; done
      keep+=("$p")
    done
    pkgs=("${keep[@]}")
  fi
  (( ${#pkgs[@]} )) || return 0
  say "Installing ${#pkgs[@]} packages via $AUR_HELPER"
  as_user "$AUR_HELPER" -S --needed "${PARU_CONFIRM[@]}" "${pkgs[@]}" || {
    # One or more packages failed (AUR build errors, 404s, etc.). Don't let
    # a single bad apple abort the whole bootstrap. Retry remaining packages
    # one at a time and warn about anything that still won't install.
    local failed=()
    for p in "${pkgs[@]}"; do
      pacman -Q "$p" >/dev/null 2>&1 && continue  # already installed
      if as_user "$AUR_HELPER" -S --needed "${PARU_CONFIRM[@]}" "$p"; then
        ok "retried: $p"
      else
        warn "FAILED to install: $p"
        failed+=("$p")
      fi
    done
    if (( ${#failed[@]} )); then
      warn "Could not install: ${failed[*]} — fix manifest or install manually later"
    fi
  }
}

install_flatpaks() {
  (( INSTALL_FLATPAK )) || return 0
  command -v flatpak >/dev/null 2>&1 || { warn "flatpak command missing; package install may have failed"; return 0; }
  say "Installing Flatpak apps"
  sudo_run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  local apps=()
  mapfile -t apps < <(pkg_lines "$DOTFILES_DIR/packages/flatpak-apps.txt")
  (( ${#apps[@]} )) || return 0
  run flatpak install "${FLATPAK_CONFIRM[@]}" flathub "${apps[@]}"
}

copy_dotfiles() {
  (( INSTALL_DOTFILES )) || return 0
  say "Copying dotfiles into $TARGET_HOME"
  local paths=(
    .bashrc .zshrc
    .config/alacritty .config/environment.d .config/gamescope .config/ghostty
    .config/hypr .config/kitty .config/mako .config/nvim .config/quickshell
    .config/starship.toml .config/swaylock .config/waybar .config/wlogout .config/wofi
  )
  local rel src dst
  sudo_run install -d -o "$TARGET_UID" -g "$TARGET_GID" "$BACKUP_ROOT/home"
  for rel in "${paths[@]}"; do
    src="$DOTFILES_DIR/$rel"
    dst="$TARGET_HOME/$rel"
    [[ -e "$src" || -L "$src" ]] || continue
    backup_home_path "$dst"
    sudo_run install -d -o "$TARGET_UID" -g "$TARGET_GID" "$(dirname "$dst")"
    sudo_run cp -a "$src" "$(dirname "$dst")/"
    sudo_run chown -R "$TARGET_UID:$TARGET_GID" "$dst"
  done
  ok "dotfiles copied (previous files backed up if present)"
}

add_user_to_group_if_present() {
  local group="$1"
  getent group "$group" >/dev/null 2>&1 || return 0
  sudo_run usermod -aG "$group" "$TARGET_USER"
}

install_gaming_deploy() {
  (( INSTALL_GAMING )) || return 0
  local deploy="$DOTFILES_DIR/deploy/gaming"
  [[ -d "$deploy" ]] || { warn "Gaming deploy directory missing: $deploy"; return 0; }
  say "Deploying Gaming Mode root/session helpers"
  for f in \
    /usr/local/bin/gaming-session-switch /usr/local/bin/switch-to-gaming \
    /usr/local/bin/switch-to-desktop /usr/local/bin/gamescope-session-wrapper \
    /usr/local/bin/gaming-keybind-monitor /usr/local/bin/gaming-desktop-restore \
    /usr/lib/os-session-select /usr/share/wayland-sessions/gamescope-gaming.desktop \
    /usr/share/applications/gaming-mode.desktop \
    /etc/systemd/system/sddm-boot-cleanup.service /etc/pacman.d/hooks/gamescope-setcap.hook \
    "$TARGET_HOME/.config/environment.d/99-gaming-session.conf" \
    "$TARGET_HOME/.config/gamescope/scripts/dell.aw3423dwf.lua"; do
    [[ "$f" == "$TARGET_HOME"* ]] && backup_home_path "$f" || backup_path "$f"
  done

  sudo_run install -Dm755 "$deploy/usr/local/bin/gaming-session-switch" /usr/local/bin/gaming-session-switch
  sudo_run install -Dm755 "$deploy/usr/local/bin/switch-to-gaming" /usr/local/bin/switch-to-gaming
  sudo_run install -Dm755 "$deploy/usr/local/bin/switch-to-desktop" /usr/local/bin/switch-to-desktop
  sudo_run install -Dm755 "$deploy/usr/local/bin/gamescope-session-wrapper" /usr/local/bin/gamescope-session-wrapper
  sudo_run install -Dm755 "$deploy/usr/local/bin/gaming-keybind-monitor" /usr/local/bin/gaming-keybind-monitor
  sudo_run install -Dm755 "$deploy/usr/local/bin/gaming-desktop-restore" /usr/local/bin/gaming-desktop-restore
  sudo_run install -Dm755 "$deploy/usr/lib/os-session-select" /usr/lib/os-session-select
  sudo_run install -Dm644 "$deploy/usr/share/wayland-sessions/gamescope-gaming.desktop" /usr/share/wayland-sessions/gamescope-gaming.desktop
  sudo_run install -Dm644 "$deploy/usr/share/applications/gaming-mode.desktop" /usr/share/applications/gaming-mode.desktop
  sudo_run install -Dm644 "$deploy/etc/systemd/system/sddm-boot-cleanup.service" /etc/systemd/system/sddm-boot-cleanup.service
  sudo_run install -Dm644 "$deploy/etc/pacman.d/hooks/gamescope-setcap.hook" /etc/pacman.d/hooks/gamescope-setcap.hook
  sudo_run install -Dm644 "$deploy/home/.config/environment.d/99-gaming-session.conf" "$TARGET_HOME/.config/environment.d/99-gaming-session.conf"
  sudo_run install -Dm644 "$deploy/home/.config/gamescope/scripts/dell.aw3423dwf.lua" "$TARGET_HOME/.config/gamescope/scripts/dell.aw3423dwf.lua"
  sudo_run chown "$TARGET_UID:$TARGET_GID" "$TARGET_HOME/.config/environment.d/99-gaming-session.conf" "$TARGET_HOME/.config/gamescope/scripts/dell.aw3423dwf.lua"

  sudo_run sed -i \
    -e "s|^LOGIN_USER=.*|LOGIN_USER=\"$TARGET_USER\"|" \
    -e "s|^GAMING_GPU_PCI=.*|GAMING_GPU_PCI=\"$GAMING_GPU_PCI\"   # gaming GPU / primary render card|" \
    -e "s|^AUX_CONNECTOR=.*|AUX_CONNECTOR=\"$GAMING_AUX_OUTPUT\"        # auxiliary connector to force off|" \
    /usr/local/bin/gaming-session-switch
  sudo_run sed -i \
    -e "s|^MESA_VK_DEVICE_SELECT=.*|MESA_VK_DEVICE_SELECT=$GAMING_VK_DEVICE|" \
    -e "s|^OUTPUT_CONNECTOR=.*|OUTPUT_CONNECTOR=$GAMING_OUTPUT|" \
    -e "s|^OUTPUT_CONNECTOR_TO_DISABLE=.*|OUTPUT_CONNECTOR_TO_DISABLE=$GAMING_AUX_OUTPUT|" \
    "$TARGET_HOME/.config/environment.d/99-gaming-session.conf"
  sudo_run chown "$TARGET_UID:$TARGET_GID" "$TARGET_HOME/.config/environment.d/99-gaming-session.conf"

  local sudoers_tmp
  sudoers_tmp="$(mktemp)"
  cat > "$sudoers_tmp" <<SUDOERS
# Deck Mode session switching: single scoped NOPASSWD rule.
$TARGET_USER ALL=(ALL) NOPASSWD: /usr/local/bin/gaming-session-switch
SUDOERS
  run chmod 0440 "$sudoers_tmp"
  if (( DRY_RUN )); then
    echo "[dry-run] sudo visudo -c -f $sudoers_tmp"
    sudo_run install -m 0440 "$sudoers_tmp" /etc/sudoers.d/gaming-session-switch
  elif sudo visudo -c -f "$sudoers_tmp" >/dev/null; then
    sudo_run install -m 0440 "$sudoers_tmp" /etc/sudoers.d/gaming-session-switch
  else
    warn "Generated sudoers rule failed validation; not installing"
  fi
  run rm -f "$sudoers_tmp"

  sudo_run systemctl daemon-reload
  sudo_run systemctl enable sddm-boot-cleanup.service
  if command -v setcap >/dev/null 2>&1 && [[ -x /usr/bin/gamescope ]]; then
    sudo_run setcap cap_sys_nice=eip /usr/bin/gamescope || warn "setcap on gamescope failed"
  fi
  add_user_to_group_if_present input
  add_user_to_group_if_present video
  add_user_to_group_if_present render
  if [[ -d "/run/user/$TARGET_UID" ]]; then
    as_user env XDG_RUNTIME_DIR="/run/user/$TARGET_UID" systemctl --user mask cachyos-gamescope-autologin.service || true
  else
    warn "User systemd bus not active; run later: systemctl --user mask cachyos-gamescope-autologin.service"
  fi
  ok "Gaming Mode helpers deployed"
}

install_pi() {
  (( INSTALL_PI )) || return 0
  say "Installing pi.dev coding agent + config"
  sudo_run pacman -S --needed "${PACMAN_CONFIRM[@]}" nodejs npm
  # User-writable npm prefix; ~/.zshrc already puts ~/.npm-global/bin on PATH.
  as_user npm install -g --prefix "$TARGET_HOME/.npm-global" \
    @earendil-works/pi-coding-agent context-mode

  local pi_src="$DOTFILES_DIR/pi" pi_dst="$TARGET_HOME/.pi/agent"
  [[ -d "$pi_src" ]] || { warn "pi config directory missing: $pi_src"; return 0; }
  backup_home_path "$pi_dst"
  sudo_run install -d -o "$TARGET_UID" -g "$TARGET_GID" "$pi_dst"
  as_user cp -rf "$pi_src/." "$pi_dst/"
  # mcp.json carries an absolute home path; rewrite for the target user.
  if [[ -f "$pi_dst/mcp.json" ]]; then
    as_user sed -i "s|/home/suraj|$TARGET_HOME|g" "$pi_dst/mcp.json"
  fi
  sudo_run chown -R "$TARGET_UID:$TARGET_GID" "$TARGET_HOME/.pi"
  ok "pi installed; auth is per-machine: run 'pi' once and log in"
}

install_sddm_theming() {
  (( INSTALL_SDDM_THEMES )) || return 0
  say "Installing SDDM themes + boot-time rotation"
  # qylock theme pack (pixel-*, girl-*, etc.)
  local cache="$TARGET_HOME/.cache/suraj-bootstrap"
  sudo_run install -d -o "$TARGET_UID" -g "$TARGET_GID" "$cache"
  if [[ ! -d "$cache/qylock" ]]; then
    as_user git clone --depth 1 https://github.com/Darkkal44/qylock.git "$cache/qylock"
  fi
  if (( DRY_RUN )); then
    echo "[dry-run] install qylock themes from $cache/qylock"
  else
    (cd "$cache/qylock" && bash "$DOTFILES_DIR/scripts/install-qylock-themes.sh")
  fi
  # Rotate a random theme before SDDM starts on every boot.
  sudo_run install -Dm755 "$DOTFILES_DIR/scripts/sddm-rotate-theme" /usr/local/bin/sddm-rotate-theme
  sudo_run install -Dm644 "$DOTFILES_DIR/scripts/sddm-rotate-theme.service" /etc/systemd/system/sddm-rotate-theme.service
  sudo_run systemctl daemon-reload
  sudo_run systemctl enable sddm-rotate-theme.service
  ok "SDDM theming deployed"
}

enable_services() {
  say "Enabling services for next boot"
  sudo_run systemctl enable NetworkManager.service bluetooth.service sddm.service
  if (( INSTALL_DAILY )); then
    sudo_run systemctl enable cups.service cups.socket cups.path || true
    systemctl list-unit-files lactd.service >/dev/null 2>&1 && sudo_run systemctl enable lactd.service || true
  fi
  if (( INSTALL_VIRT )); then
    add_user_to_group_if_present libvirt
    sudo_run systemctl enable libvirtd.service libvirtd.socket virtlogd.socket virtlockd.socket || true
  fi
  if (( INSTALL_LAPTOP )); then
    sudo_run systemctl enable power-profiles-daemon.service || true
  fi
  ok "service enablement complete (reboot recommended)"
}

main() {
  if (( ! INTERACTIVE && ARG_COUNT == 0 )) && [[ -t 0 && -t 1 ]]; then
    INTERACTIVE=1
  fi
  if (( INTERACTIVE )); then interactive_menu; fi
  resolve_gpu_kind
  confirm_plan
  sudo_keepalive
  ensure_home_dirs
  ensure_multilib
  ensure_cachyos
  ensure_paru

  local manifests=()
  (( INSTALL_DESKTOP )) && manifests+=("$DOTFILES_DIR/packages/desktop-core.txt")
  (( INSTALL_DAILY )) && manifests+=("$DOTFILES_DIR/packages/daily-apps.txt")
  (( INSTALL_GAMING )) && manifests+=("$DOTFILES_DIR/packages/gaming-mode.txt")
  [[ "$GPU_KIND" != none ]] && manifests+=("$DOTFILES_DIR/packages/gpu-$GPU_KIND.txt")
  (( INSTALL_LAPTOP )) && manifests+=("$DOTFILES_DIR/packages/laptop.txt")
  (( INSTALL_VIRT )) && manifests+=("$DOTFILES_DIR/packages/virtualization.txt")
  (( INSTALL_FULL_CURRENT )) && manifests+=("$DOTFILES_DIR/packages/current-explicit.txt" "$DOTFILES_DIR/packages/current-aur.txt")
  install_packages "${manifests[@]}"
  install_flatpaks
  copy_dotfiles
  install_gaming_deploy
  install_sddm_theming
  install_pi
  enable_services

  say "DONE"
  echo "Reboot, then log into Hyprland. Gaming Mode switch: Super+Shift+S; return: Super+Shift+R."
  echo "If groups changed, the reboot/relogin is required. Backups: $BACKUP_ROOT"
}

main "$@"
