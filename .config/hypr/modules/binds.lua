-- Programs
local terminal = "ghostty"
local fileManager = "thunar"

-- MainMod key
local mainMod = "SUPER"

-- Multimedia
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))

-- Screenshot
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

-- Persistent per-workspace floating mode (replaces old workspaceopt allfloat).
-- Toggling floats every existing window on the active workspace AND auto-floats
-- any window opened there afterwards, until toggled off again.
local float_mode = {} -- [workspace id] = true while that workspace is all-float

local function toggle_workspace_float()
	local ws = hl.get_active_workspace()
	if not ws then
		return
	end
	local enable = not float_mode[ws.id]
	float_mode[ws.id] = enable or nil
	local act = enable and "enable" or "disable"
	for _, w in ipairs(ws:get_windows()) do
		hl.dispatch(hl.dsp.window.float({ action = act, window = w }))
	end
end

-- New windows opening on a float-mode workspace float automatically.
hl.on("window.open", function(w)
	if w and w.workspace and float_mode[w.workspace.id] and not w.floating then
		hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
	end
end)

-- Windows moved into a float-mode workspace float too.
hl.on("window.move_to_workspace", function(w, ws)
	if w and ws and float_mode[ws.id] and not w.floating then
		hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
	end
end)

hl.bind(mainMod .. " + SHIFT + F", toggle_workspace_float)
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.window.pseudo())
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("qs msg wallpicker toggle"))

-- Move focus (mainMod) / move window (mainMod + SHIFT) with arrow keys
for key, dir in pairs({ left = "l", right = "r", up = "u", down = "d" }) do
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = dir }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end

-- Switch to (mainMod) / move window to (mainMod + SHIFT) workspaces 1..5,
-- mapped onto keys 6 7 8 9 0
for i, key in ipairs({ "6", "7", "8", "9", "0" }) do
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.workspace.toggle_special("magic"))
hl.bind("ALT + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Native scratchpad keybinds
hl.bind("ALT + M", hl.dsp.workspace.toggle_special("spotify"))
hl.bind("ALT + return", hl.dsp.workspace.toggle_special("term"))
