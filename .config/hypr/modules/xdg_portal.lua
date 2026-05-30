-- xdg-desktop-portal startup helper
-- Replaces ~/.config/hypr/scripts/xdg-portal-hyprland.

local M = {}

hl.on("hyprland.start", function()
	hl.exec_cmd(table.concat({
		"sleep 1",
		"killall xdg-desktop-portal-hyprland",
		"killall xdg-desktop-portal-wlr",
		"killall xdg-desktop-portal",
		"/usr/lib/xdg-desktop-portal-hyprland & sleep 2",
		"/usr/lib/xdg-desktop-portal &",
	}, "; "))
end)

return M
