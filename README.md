# arch_hyprland_dots
This is my in progress dotfiles for me home config of arch. This is for hyprland but I will be making a repository for Qtile for learning.

[Demo Video][![Video](https://img.youtube.com/vi/vaMaudCnLJ8/maxresdefault.jpg)](https://www.youtube.com/watch?v=vaMaudCnLJ8)


## Initial installation
This can be done manually or via archinstall. if done via archinstall then choose ly as the initial login manager. Also choose pipewire

We can then disable the ly service and install SDDM below and set up a autologin via sudo usermod -aG autologin "username".

```
sudo pacman -S --needed base-devel
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

Legacy one-shot package list, kept as a rough reference:

```bash
paru -S hyprland hyprlock polkit-kde-agent viewnior       \
pavucontrol thunar thunar-archive-plugin wl-clipboard              \
wf-recorder wofi grimblast-git ffmpegthumbnailer tumbler           \
playerctl ghostty starship waybar wlogout-git swaylock-effects-git \
wlsunset sddm sddm-theme-tokyo-night-git pamixer cliphist         \
nwg-look nwg-displays nordic-theme papirus-icon-theme             \
dunst mako otf-sora ttf-nerd-fonts-symbols-common otf-firamono-nerd \
inter-font ttf-fantasque-nerd noto-fonts noto-fonts-emoji         \
ttf-comfortaa ttf-jetbrains-mono-nerd ttf-icomoon-feather         \
ttf-iosevka-nerd adobe-source-code-pro-fonts woff2-font-awesome   \
ttf-meslo-nerd-font-powerlevel10k brightnessctl gnome-disk-utility \
qt5-wayland qt6-wayland udiskie adwaita-dark leafpad firefox git  \
fastfetch pacman-contrib matugen-bin quickshell                   \
grim slurp pipewire pipewire-alsa pipewire-jack pipewire-pulse    \
wireplumber gst-plugin-pipewire networkmanager btop
```

### Terminal / prompt

Ghostty is the primary terminal and Starship is the shell prompt.

Config paths:

```text
.config/ghostty/config
.config/starship.toml
.zshrc
```

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

## Windows Terminal

Windows Terminal ricing is saved at:

```text
windows/windows-terminal/settings.json
```

Restore on Windows:

```powershell
Copy-Item .\windows\windows-terminal\settings.json "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
```
