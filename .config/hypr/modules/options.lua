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
