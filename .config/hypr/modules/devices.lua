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

-- Trackpad gestures
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
