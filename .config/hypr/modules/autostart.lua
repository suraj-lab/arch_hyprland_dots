-- Launch apps. `uwsm app --` runs each in its own systemd scope (SPEC Phase 7): under uwsm they
-- stop cleanly before the compositor; in the plain session it works the same way.
hl.on("hyprland.start", function()
	hl.exec_cmd("uwsm app -- quickshell")
	hl.exec_cmd("uwsm app -- awww-daemon")
	hl.exec_cmd("uwsm app -- spotify-launcher")
	hl.exec_cmd("uwsm app -- udiskie --no-tray --notify") -- automount + "device added" toasts; the shell's devices surface ejects
	hl.exec_cmd("uwsm app -- wl-paste --type text --watch cliphist store")
	hl.exec_cmd("uwsm app -- wl-paste --type image --watch cliphist store")
	-- The systemd user manager outlives logout, so portals from the previous session are
	-- stale (xdg-desktop-portal-hyprland dies with the old compositor and hits start-limit).
	-- After importing the new env, stop them; D-Bus re-activates them on first use.
	hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP && systemctl --user stop xdg-desktop-portal.service xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service; systemctl --user reset-failed xdg-desktop-portal-hyprland.service xdg-desktop-portal.service xdg-desktop-portal-gtk.service")
	hl.exec_cmd("uwsm app -- wl-clip-persist --clipboard regular") -- keep copied text after the source app closes
	hl.exec_cmd("uwsm app -- hyprsunset --identity") -- the shell applies the schedule (settings.json nightLight)
	hl.exec_cmd("uwsm app -- hypridle") -- lock on lock-session/before sleep; idle timers stay in the shell
	hl.exec_cmd("~/.config/quickshell/scripts/apply-theme.sh")
	hl.exec_cmd("mozillavpn activate")
	-- lianli-daemon is PartOf=graphical-session.target, so leaving any session (e.g. Gaming Mode)
	-- stops it, and this plain Hyprland session never starts that target again. No-op if running.
	hl.exec_cmd("systemctl --user start lianli-daemon.service")
	-- Deck Mode: remove transient SDDM autologin + recover portals/pipewire
	-- when returning from Gaming Mode (no-op on normal logins).
	hl.exec_cmd("/usr/local/bin/gaming-desktop-restore")
end)
