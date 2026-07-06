---
name: arch
description: Arch Linux system management, packages, services, debugging
---
# Arch Skill

## Package Management
pacman -Ss <term>          # search
sudo pacman -S <pkg>       # install
paru -S <pkg>               # AUR install
pacman -Ql <pkg>           # files in package
pacman -Qo <file>          # what owns file
pacman -Rns <pkg>          # remove with deps

## Systemd
systemctl status <service>
systemctl --user status <service>
sudo systemctl enable --now <service>
journalctl -u <service> -n 50
journalctl --user -u <service> -n 50

## Common Locations
~/.config/          # user configs
~/.local/share/     # user data
/etc/               # system configs
~/.local/bin/       # user scripts

## Debugging
dmesg | tail -20               # kernel messages
journalctl -b -p err           # boot errors
systemctl --failed             # failed services
