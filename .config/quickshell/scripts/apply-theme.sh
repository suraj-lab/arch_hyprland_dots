#!/usr/bin/env bash
# Idempotent GTK theme setup, run from Hyprland autostart (replaces GTK_THEME=Adwaita:dark,
# which breaks libadwaita apps and doesn't reach D-Bus-started ones like portal file dialogs).
# gsettings is what GTK3/4 read on Wayland; settings.ini is kept in sync for X11/fallback.
# Icons, fonts and cursor are left as they are. Wallpaper colours come from matugen
# (run by extract-accent.sh on every wallpaper change); generated here only if missing.
set -u

gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

ini="$HOME/.config/gtk-3.0/settings.ini"
if [[ -f "$ini" ]]; then
    sed -i -e 's/^gtk-theme-name=.*/gtk-theme-name=adw-gtk3-dark/' \
           -e 's/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=1/' "$ini"
fi

# First login / fresh install: no generated colours yet -> build them from the cached shell
# accent (theme monitor), else the shell's default accent.
if [[ ! -f "$HOME/.config/qt6ct/colors/matugen.conf" ]] && command -v matugen >/dev/null; then
    accent=$(cat "$HOME/.cache/quickshell/accent-${THEME_MONITOR:-DP-2}" "$HOME/.cache/quickshell/accent" 2>/dev/null | head -1)
    [[ "$accent" =~ ^#[0-9a-fA-F]{6}$ ]] || accent="#00ffea"
    matugen color hex "$accent" -c "$HOME/.config/matugen/config.toml" -m dark -t scheme-vibrant -q
fi
