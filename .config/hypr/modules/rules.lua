-- Gaming: immediate (tearing-capable) page flips for games.
-- general:allow_tearing is on; tearing only activates for windows with the
-- `immediate` rule, so the desktop is unaffected.
for _, class in ipairs({ "^steam_app_.*", "^gamescope$" }) do
	hl.window_rule({ match = { class = class }, immediate = true })
end

-- BBE RDP (bbe-rdp): fullscreen per monitor, but low/variable frame rate makes
-- the OLED flicker with VRR (DP-2 vrr = 2 engages it for fullscreen apps).
hl.window_rule({ match = { class = "^com\\.freerdp\\.client\\.sdl3$" }, no_vrr = true })
-- The remote desktop repaints constantly: no inactive transparency (and the
-- full-size re-blur behind it), no shadow/rounding/animations to composite.
hl.window_rule({
	match = { class = "^com\\.freerdp\\.client\\.sdl3$" },
	opacity = "1.0 override 1.0 override",
	no_blur = true,
	no_shadow = true,
	no_dim = true,
	no_anim = true,
	rounding = 0,
})
-- bbe-rdp --windowed (patched FreeRDP): titles end in "[<display name> (<output>)]"
hl.window_rule({ match = { initial_title = "^FreeRDP: .*\\(DP-2\\)\\]$" }, workspace = "name:rdp-main" })
hl.window_rule({ match = { initial_title = "^FreeRDP: .*\\(HDMI-A-1\\)\\]$" }, workspace = "name:rdp-side" })

-- Zoom: behave like on a floating desktop. Every Zoom window (meeting, video panel,
-- share toolbar) floats where it opens, so none can tile into rdp-main/rdp-side
-- (shrinking the RDP window would resize the remote desktop).
hl.window_rule({ match = { class = "^zoom$" }, float = true })

-- Spotify window rules
hl.window_rule({ match = { class = "Spotify" }, workspace = "special:spotify silent" })
hl.window_rule({ match = { class = "Spotify" }, float = true })
hl.window_rule({ match = { class = "Spotify" }, size = { "75%", "65%" } })
hl.window_rule({ match = { class = "Spotify" }, center = true })

-- Bar + overview: blur with popup blur and alpha threshold
for _, ns in ipairs({ "quickshell", "quickshell-overview" }) do
	hl.layer_rule({ match = { namespace = ns }, blur = true })
	hl.layer_rule({ match = { namespace = ns }, blur_popups = true })
	hl.layer_rule({ match = { namespace = ns }, ignore_alpha = 0.3 })
end

-- All overlays (incl. overview): no slide animation
for _, ns in ipairs({
	"quickshell-launcher",
	"quickshell-wallpicker",
	"quickshell-session",
	"quickshell-screenshot",
	"quickshell-overview",
}) do
	hl.layer_rule({ match = { namespace = ns }, animation = "none" })
end

-- Launcher-style overlays: no blur (overview keeps its blur)
for _, ns in ipairs({
	"quickshell-launcher",
	"quickshell-wallpicker",
	"quickshell-session",
	"quickshell-screenshot",
}) do
	hl.layer_rule({ match = { namespace = ns }, blur = false })
end
