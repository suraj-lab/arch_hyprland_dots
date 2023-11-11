# arch_hyprland_dots
This is my in progress dotfiles for me home config of arch. This is for hyprland but I will be making a repository for Qtile for learning.

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

```bash
paru -S hyprland polkit-kde-agent ffmpeg viewnior wofi         \
pavucontrol thunar wl-clipboard wf-recorder swaybg swww        \
waypaper grimblast-git ffmpegthumbnailer tumbler playerctl     \
wl-paste thunar-archive-plugin alacritty waybar wlogout        \
swaylock swaylock-effects wlsunset sddm-git pamixer cliphist   \
nwg-look-bin nordic-theme papirus-icon-theme dunst otf-sora    \
ttf-nerd-fonts-symbols-common otf-firamono-nerd inter-font     \
ttf-fantasque-nerd noto-fonts noto-fonts-emoji ttf-comfortaa   \
ttf-jetbrains-mono-nerd ttf-icomoon-feather ttf-iosevka-nerd   \
adobe-source-code-pro-fonts brightnessctl gnome-disk-utility   \
qt5-wayland qt6-wayland ttf-font-awesome udiskie adwaita-dark  \
ttf-meslo-nerd-font-powerlevel10k leafpad firefox git	       \

```

### Additional Packages (for QOL and general use)

```bash
paru -S qemu-full virt-manager virt-viewer vde2 ebtables \
iptables-nft nftables dnsmasq bridge-utils ovmf swtpm	 \
dmidecode  gpu-passthrough-manager mozillavpn 		 \
spotify-launcher spicetify-cli xwaylandvideobridge-git   \
xdg-desktop-portal-hyprland mpv ani-cli			 \	 			 \
```

### Gaming on Arch

```bash
paru -R amdvlk lib32-amdvlk 				 \
paru -S vulkan-radeon lib32-vulkan-radeon 		 \
paru -S steam gamemode webcord mangohud goverlay	 \
```

### Work related

```bash
paru -S icaclient webex-bin zoom
```