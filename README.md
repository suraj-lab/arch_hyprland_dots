# arch_hyprland_dots
This is my in progress dotfiles for me home config of arch. This is for hyprland but I will be making a repository for Qtile for learning.

[Demo Video][![Video](https://img.youtube.com/vi/vaMaudCnLJ8/maxresdefault.jpg)](https://www.youtube.com/watch?v=vaMaudCnLJ8)


## The desktop

- **Session:** log in through SDDM as **Hyprland (uwsm-managed)**. uwsm runs Hyprland and every
  app as systemd units, so logout shuts them down in order. Plain **Hyprland** stays
  selectable as a fallback.
- **Hyprland** is configured in Lua: `.config/hypr/hyprland.lua` loads `modules/`
  (monitors, env, autostart, binds, rules, animations, options, devices, wallpaper).
- **Quickshell** (`.config/quickshell/`) is the whole shell: a thin frame around each monitor and
  a pill at the bottom centre that grows into the bar row and its surfaces (dashboard,
  launcher, clipboard, sound, notifications, network, Bluetooth, devices, updates, settings,
  keybind cheatsheet). Toasts and the volume/brightness OSD slide in from the edges. It is also
  the notification daemon and the polkit (password prompt) agent.
- **Gaming Mode** (`Super+Shift+S`) switches to a SteamOS-style gamescope session and back. Steam's
  *Switch to Desktop*, `Super+Shift+R` inside Gaming Mode, or a reboot return to the desktop.
  See `docs/gaming-mode.md`.

### Keybinds

`Super+/` shows all of them in the shell, read live from Hyprland.

| Keys | Action |
|---|---|
| `Super+Return` / `Super+E` / `Super+B` | terminal (Ghostty) / file manager (Thunar) / Firefox |
| `Super+Space` | launcher: apps, `=` calculator, `>` actions |
| `Super+V` | clipboard history |
| `Super+D` | dashboard |
| `Super` double-tap | peek the pill |
| `Super+W` / `Super+Shift+W` | workspace overview / wallpaper picker |
| `Super+C` | close window |
| `Super+F` / `Super+P` / `Super+Shift+P` | fullscreen / toggle floating / pseudo-tile |
| `Super+Shift+F` | float the whole workspace (new windows too) |
| `Super+arrows` / `Super+Shift+arrows` | focus / move window |
| `Super+6..0` / `Super+Shift+6..0` | go to / move window to workspace 1-5 |
| `Super+scroll`, `Super+LMB/RMB drag` | next/previous workspace, move/resize window |
| `Super+Shift+N` / `Alt+Shift+S` | toggle scratchpad / move window there |
| `Alt+M` / `Alt+Return` | Spotify / terminal scratchpads |
| `Print` / `Ctrl+Shift+S` | screenshot whole screen / area |
| `Ctrl+Alt+L` | lock |
| `Super+Shift+S` | Gaming Mode |
| media keys | volume, mute, mic mute, play/pause, next/previous |

### Packages

`packages/desktop-core.txt` holds official-repo packages only (core/extra/multilib), checked by
`scripts/check-official.sh packages/desktop-core.txt`. AUR and personal apps live in the other
manifests. After editing `desktop-core.txt`, run `scripts/sync-readme-pkglist.sh`.

### Theming

Pick a wallpaper with `Super+Shift+W`. `extract-accent.sh` takes each monitor's accent colour
from its wallpaper and runs matugen, which writes GTK 3/4, qt5ct/qt6ct, Ghostty and Hyprland
colours from `.config/matugen/templates`. `apply-theme.sh` applies the GTK theme through gsettings at
login. Icons, fonts and the cursor are left as they are.

### Settings

The shell's Settings surface (launcher `>settings`, or *All settings* in the System view)
writes `~/.config/quickshell/settings.json`, which the shell reloads on every change. Missing or
invalid values fall back to these defaults:

| Key | Default | Meaning |
|---|---|---|
| `idle.lockSec` / `idle.dpmsSec` / `idle.suspendSec` | 600 / 900 / 0 | lock, screens off, suspend after N seconds idle (0 = never) |
| `idle.caffeine` | `false` | keep the session awake (remembered across restarts) |
| `nightLight.temperature` | 4000 | colour temperature in K (1000-6500) |
| `nightLight.from` / `nightLight.to` | `"19:30"` / `"09:00"` | night light schedule (may wrap past midnight) |
| `appearance.animations` | `true` | pill and surface animations |
| `pill.restStyle` | `"tab"` | pill at rest: `"tab"` (clock + workspaces) or `"handle"` |
| `pill.hoverExpand` | `true` | grow the pill when the pointer reaches it |
| `pill.collapseDelayMs` | 700 | delay before the pill collapses (0-5000) |
| `monitors.<output>.pill.*` | | the same pill keys for one monitor, e.g. `monitors.HDMI-A-1` |
| `gaming.autoGameMode` | `true` | desktop Game Mode (DND on, effects off) while a game runs |
| `weather.location` | `""` | wttr.in location (empty: located by IP) |
| `brightness.buses` | `{}` | DDC/CI bus per output for ddcutil, e.g. `{"DP-2": 5}` (empty: detected) |

The plan and history of this setup are in `docs/de-upgrade/SPEC.md`.

## Initial installation
This can be done manually or via archinstall. If done via archinstall, choose a minimal/Hyprland-capable install with NetworkManager and PipeWire.

### One-shot bootstrap

The new bootstrap script is the preferred fresh-install path. It is tailored to my current Arch/CachyOS Hyprland workstation and installs:

- desktop dotfiles and Hyprland/Quickshell config
- current daily apps from curated package manifests
- GPU drivers auto-detected via `lspci` (AMD/NVIDIA/Intel, `--gpu` overrides)
- SteamOS-style Gaming Mode helpers from the validated `arch-gaming-optimization` work
- qylock SDDM theme pack + boot-time random theme rotation
- pi.dev coding agent + captured config from `pi/` (auth is per-machine)
- Flatpak apps
- system services needed after reboot

Virtualization/passthrough tools are opt-in via `--virt`; laptop extras via `--laptop`.

From the Arch ISO, pre-seed archinstall (only disk + passwords asked):

```bash
archinstall --config-url https://da.gd/surajarch
```

(Permanent short link to `deploy/archinstall.json` on master; long form: `https://raw.githubusercontent.com/suraj-lab/arch_hyprland_dots/master/deploy/archinstall.json`.)

Then after first login:

```bash
sudo pacman -S --needed git
mkdir -p ~/Projects/Dotfiles
git clone <this-repo-url> ~/Projects/Dotfiles/arch_hyprland_dots
cd ~/Projects/Dotfiles/arch_hyprland_dots
./scripts/bootstrap-arch.sh   # no args on a terminal = interactive component menu + hardware detection
reboot
```

Fully scripted instead:

```bash
./scripts/bootstrap-arch.sh --yes
```

Preview without changing the system:

```bash
./scripts/bootstrap-arch.sh --dry-run
```

Useful profile flags:

```bash
./scripts/bootstrap-arch.sh -i                 # force the interactive menu
./scripts/bootstrap-arch.sh --minimal          # desktop-core + dotfiles only
./scripts/bootstrap-arch.sh --no-gaming        # skip Gaming Mode deployment
./scripts/bootstrap-arch.sh --gpu nvidia       # override GPU driver auto-detection
./scripts/bootstrap-arch.sh --laptop           # add power-profiles-daemon + brightnessctl
./scripts/bootstrap-arch.sh --virt             # also install virtualization stack
./scripts/bootstrap-arch.sh --full-current     # also install captured current package lists
./scripts/bootstrap-arch.sh --help
```

More detail and the generalization roadmap are in `docs/bootstrap.md`.

Legacy/manual AUR helper bootstrap:

```bash
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si
```

### Dependencies

The package manifests are now split for reinstall/ISO work:

```bash
grep -hvE '^\s*(#|$)' packages/desktop-core.txt | paru -S --needed -
grep -hvE '^\s*(#|$)' packages/gaming-mode.txt | paru -S --needed -
```

For the full SteamOS-style Gaming Mode bootstrap:

```bash
./scripts/install-gaming-mode.sh
```

Backup one-shot package list, generated from `packages/desktop-core.txt` — run `scripts/sync-readme-pkglist.sh` after changing the manifest:

<!-- pkglist:begin (generated by scripts/sync-readme-pkglist.sh) -->
```bash
paru -S --needed base-devel git hyprland hyprlock quickshell uwsm qt6-5compat \
qt5-wayland qt6-wayland sddm ghostty starship firefox thunar \
thunar-archive-plugin mpv viewnior pavucontrol wl-clipboard cliphist \
playerctl hyprsunset awww matugen grim slurp hyprpicker imagemagick \
pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber \
gst-plugin-pipewire xdg-desktop-portal-hyprland networkmanager btop \
fastfetch nwg-look nwg-displays adw-gtk-theme papirus-icon-theme \
noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd \
ttf-nerd-fonts-symbols-common xdg-desktop-portal-gtk gnome-keyring \
libsecret seahorse qt6ct qt5ct xdg-user-dirs wl-clip-persist hypridle \
pacman-contrib udisks2 udiskie gvfs gvfs-mtp gvfs-smb bluez \
bluez-utils ddcutil system-config-printer libqalculate
```
<!-- pkglist:end -->

### Additional Packages (for QOL and general use)

```bash
paru -S qemu-full virt-manager virt-viewer vde2 nftables          \
dnsmasq bridge-utils edk2-ovmf swtpm dmidecode                    \
gpu-passthrough-manager mozillavpn spotify-launcher               \
spicetify-cli xwaylandvideobridge-git xdg-desktop-portal-hyprland \
vlc ani-cli obs-studio looking-glass opencl-amd-dev               \
deluge deluge-gtk localsend-bin vscodium-bin flatpak              \
remmina freerdp imagemagick
```

### Gaming on Arch

Validated Gaming Mode / Deck Mode details are in `docs/gaming-mode.md`.

Quick package restore:

```bash
paru -R amdvlk lib32-amdvlk
grep -hvE '^\s*(#|$)' packages/gaming-mode.txt | paru -S --needed -
```

The private `arch-gaming-optimization` repo contains the full root-helper deployment, verifier, troubleshooting notes, and hardware-specific scripts.

### Work related

```bash
paru -S icaclient zoom lmstudio-bin
```

## SDDM Theming

Login screen uses [qylock](https://github.com/Darkkal44/qylock) SDDM themes
with automatic rotation on every boot.

### Dependencies

```bash
paru -S --needed qt6-declarative qt6-5compat qt6-svg \
    qt6-multimedia qt6-multimedia-ffmpeg \
    gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly \
    fzf
```

### Install themes

```bash
git clone https://github.com/Darkkal44/qylock ~/Projects/qylock
cd ~/Projects/qylock
~/Projects/Dotfiles/arch_hyprland_dots/scripts/install-qylock-themes.sh
```

This copies all themes into `/usr/share/sddm/themes/`.
Clockwork sub-variants (orbital, tape) are installed as `clockwork-orbital`
and `clockwork-tape`.

### Theme rotation

A systemd oneshot service picks a random theme before SDDM starts:

```bash
cd ~/Projects/Dotfiles/arch_hyprland_dots
./scripts/install-sddm-rotation.sh
```

Manual run (sets a random theme immediately, displayed on next login):

```bash
sudo systemctl start sddm-rotate-theme
```

### Set a specific theme

To lock a single theme instead of rotating:

```bash
# Disable rotation first
sudo systemctl disable sddm-rotate-theme.service

# Pick your theme (list: ls /usr/share/sddm/themes/)
sudo sed -i 's/^Current=.*/Current=clockwork-tape/' /etc/sddm.conf.d/theme.conf
```

## Windows Terminal

Windows Terminal ricing is saved at:

```text
windows/windows-terminal/settings.json
```

Restore on Windows:

```powershell
Copy-Item .\windows\windows-terminal\settings.json "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
```
