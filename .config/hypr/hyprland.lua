
-- Monitors
hl.monitor({
	output = "DP-2",
	mode = "preferred",
	position = "1920x-400",
	scale = 1,
	vrr = 2,
	bitdepth = 10,
	cm = "hdr",
	sdrbrightness = 1.0,
	sdrsaturation = 1.0,
})
hl.monitor({
	output = "desc:ViewSonic Corporation VX2476 Series UPA213310203",
	mode = "1920x1080@74",
	position = "0x0",
	scale = 1,
})
hl.monitor({ output = "DP-4", disabled = true })
hl.monitor({ output = "DP-5", disabled = true })

-- Programs
local terminal = "ghostty"
local fileManager = "thunar"

-- Launch apps
hl.on("hyprland.start", function()
	hl.exec_cmd("quickshell")
	hl.exec_cmd("awww-daemon")
	hl.exec_cmd("spotify-launcher")
	hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
	hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
	hl.exec_cmd("wl-clipboard-history -t")
	hl.exec_cmd("wlsunset -S 9:00 -s 19:30")
	hl.exec_cmd("mozillavpn activate")
end)

-- Modules
require("modules.wallpaper")
require("modules.xdg_portal")

-- Environment
hl.env("XCURSOR_SIZE", "24")
hl.env("GTK_THEME", "Adwaita:dark")
hl.env("WLR_DRM_NO_ATOMIC", "1")

-- Options
hl.config({
	input = {
		kb_layout = "gb",
		kb_variant = "",
		kb_model = "",
		kb_options = "",
		kb_rules = "",
		follow_mouse = 1,
		touchpad = {
			natural_scroll = false,
		},
		sensitivity = 0,
	},

	general = {
		gaps_in = 7,
		gaps_out = 11,
		border_size = 2,
		layout = "dwindle",
		allow_tearing = true,
	},

	decoration = {
		rounding = 10,
		blur = {
			enabled = true,
			size = 6,
			passes = 3,
			new_optimizations = true,
			ignore_opacity = true,
		},
		active_opacity = 1.0,
		inactive_opacity = 0.8,
		fullscreen_opacity = 1.0,
	},

	animations = {
		enabled = true,
	},

	dwindle = {
		preserve_split = true,
	},

	master = {
		new_status = "master",
	},

	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		mouse_move_enables_dpms = true,
		enable_swallow = true,
		swallow_regex = "^(ghostty)$",
	},
})

-- Animations: macOS-like, snappy, controlled motion
hl.curve("macSpring", { type = "spring", mass = 1, stiffness = 95, dampening = 18 })
hl.curve("macSoftSpring", { type = "spring", mass = 1, stiffness = 75, dampening = 16 })
hl.curve("snappyOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("smoothFocus", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })
hl.curve("default", { type = "bezier", points = { { 0, 1 }, { 0, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 4.2, spring = "macSpring" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.0, spring = "macSpring", style = "popin 85%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.4, bezier = "snappyOut", style = "popin 88%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.4, spring = "macSpring" })
hl.animation({ leaf = "border", enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 2.5, bezier = "snappyOut" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 6, bezier = "smoothFocus" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 6, bezier = "smoothFocus" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.2, spring = "macSoftSpring", style = "slidefade 18%" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 3.2, bezier = "snappyOut", style = "popin 90%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2.2, bezier = "snappyOut", style = "fade" })

-- Mouse
hl.device({
	name = "epic-mouse-v1",
	sensitivity = -0.5,
})

-- Apple Magic Trackpad
hl.device({
	name = "apple-inc.-magic-trackpad",
	sensitivity = 0.35,
	natural_scroll = true,
	scroll_factor = 0.65,
	clickfinger_behavior = true,
	tap_to_click = true,
	tap_and_drag = true,
	drag_lock = 1,
})

hl.device({
	name = "apple-inc.-magic-trackpad-1",
	sensitivity = 0.35,
	natural_scroll = true,
	scroll_factor = 0.65,
	clickfinger_behavior = true,
	tap_to_click = true,
	tap_and_drag = true,
	drag_lock = 1,
})

-- Multimedia
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))

-- MainMod key
local mainMod = "SUPER"

-- Screenshot
local screenshotarea =
	[[hyprctl keyword animation "fadeOut,0,0,default"; grimblast --notify copysave area; hyprctl keyword animation "fadeOut,1,4,default"]]
hl.bind("CTRL + SHIFT + S", hl.dsp.exec_cmd("qs msg screenshot area"))
hl.bind("Print", hl.dsp.exec_cmd("qs msg screenshot screen"))

-- Keybinds
hl.bind(mainMod .. " + return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + P", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("qs msg launcher toggle"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("qs msg overview toggle"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("killall wofi || cliphist list | wofi --dmenu | cliphist decode | wl-copy"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.window.pseudo())
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("qs msg wallpicker toggle"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "d" }))
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.move({ direction = "d" }))

-- Switch workspaces with mainMod + [0-9]
hl.bind(mainMod .. " + 6", hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + 7", hl.dsp.focus({ workspace = 2 }))
hl.bind(mainMod .. " + 8", hl.dsp.focus({ workspace = 3 }))
hl.bind(mainMod .. " + 9", hl.dsp.focus({ workspace = 4 }))
hl.bind(mainMod .. " + 0", hl.dsp.focus({ workspace = 5 }))

-- Move active window to a workspace with mainMod + SHIFT + [0-9]
hl.bind(mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 1 }))
hl.bind(mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 2 }))
hl.bind(mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 3 }))
hl.bind(mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 4 }))
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 5 }))

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.workspace.toggle_special("magic"))
hl.bind("ALT + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Trackpad gestures
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Spotify window rules
hl.window_rule({ match = { class = "Spotify" }, workspace = "special:spotify silent" })
hl.window_rule({ match = { class = "Spotify" }, float = true })
hl.window_rule({ match = { class = "Spotify" }, size = { "75%", "65%" } })
hl.window_rule({ match = { class = "Spotify" }, center = true })

-- Native scratchpad keybinds
hl.bind("ALT + M", hl.dsp.workspace.toggle_special("spotify"))
hl.bind("ALT + return", hl.dsp.workspace.toggle_special("term"))

-- Blur
hl.layer_rule({ match = { namespace = "quickshell" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell" }, blur_popups = true })
hl.layer_rule({ match = { namespace = "quickshell" }, ignore_alpha = 0.3 })

-- Overlay namespaces (no slide animation)
hl.layer_rule({ match = { namespace = "quickshell-launcher" }, animation = "none" })
hl.layer_rule({ match = { namespace = "quickshell-launcher" }, blur = false })
hl.layer_rule({ match = { namespace = "quickshell-wallpicker" }, animation = "none" })
hl.layer_rule({ match = { namespace = "quickshell-wallpicker" }, blur = false })
hl.layer_rule({ match = { namespace = "quickshell-session" }, animation = "none" })
hl.layer_rule({ match = { namespace = "quickshell-session" }, blur = false })
hl.layer_rule({ match = { namespace = "quickshell-screenshot" }, animation = "none" })
hl.layer_rule({ match = { namespace = "quickshell-screenshot" }, blur = false })
hl.layer_rule({ match = { namespace = "quickshell-overview" }, animation = "none" })
hl.layer_rule({ match = { namespace = "quickshell-overview" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell-overview" }, blur_popups = true })
hl.layer_rule({ match = { namespace = "quickshell-overview" }, ignore_alpha = 0.3 })
