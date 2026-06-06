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
