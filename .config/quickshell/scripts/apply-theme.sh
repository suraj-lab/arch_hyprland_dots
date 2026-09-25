#!/usr/bin/env bash
# Idempotent GTK theme setup, run from Hyprland autostart (replaces GTK_THEME=Adwaita:dark,
# which breaks libadwaita apps and doesn't reach D-Bus-started ones like portal file dialogs).
# gsettings is what GTK3/4 read on Wayland; settings.ini is kept in sync for X11/fallback.
# Icons, fonts and cursor are left as they are. Wallpaper colours: see DE-upgrade Task 2.3b.
set -u

gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

ini="$HOME/.config/gtk-3.0/settings.ini"
if [[ -f "$ini" ]]; then
    sed -i -e 's/^gtk-theme-name=.*/gtk-theme-name=adw-gtk3-dark/' \
           -e 's/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=1/' "$ini"
fi
