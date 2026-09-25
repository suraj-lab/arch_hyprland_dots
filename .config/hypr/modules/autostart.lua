-- Launch apps
hl.on("hyprland.start", function()
	hl.exec_cmd("quickshell")
	hl.exec_cmd("awww-daemon")
	hl.exec_cmd("spotify-launcher")
	hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
	-- The systemd user manager outlives logout, so portals from the previous session are
	-- stale (xdg-desktop-portal-hyprland dies with the old compositor and hits start-limit).
	-- After importing the new env, stop them; D-Bus re-activates them on first use.
	hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP && systemctl --user stop xdg-desktop-portal.service xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service; systemctl --user reset-failed xdg-desktop-portal-hyprland.service xdg-desktop-portal.service xdg-desktop-portal-gtk.service")
	hl.exec_cmd("wl-clip-persist --clipboard regular") -- keep copied text after the source app closes
	hl.exec_cmd("hyprsunset") -- schedule: ~/.config/hypr/hyprsunset.conf
	hl.exec_cmd("~/.config/quickshell/scripts/apply-theme.sh")
	hl.exec_cmd("mozillavpn activate")
	-- Deck Mode: remove transient SDDM autologin + recover portals/pipewire
	-- when returning from Gaming Mode (no-op on normal logins).
	hl.exec_cmd("/usr/local/bin/gaming-desktop-restore")
end)
