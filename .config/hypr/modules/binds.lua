-- Programs
local terminal = "ghostty"
local fileManager = "thunar"

-- MainMod key
local mainMod = "SUPER"

-- Multimedia
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+"), { description = "Media: Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), { description = "Media: Volume down" })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { description = "Media: Mute audio" })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { description = "Media: Mute microphone" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { description = "Media: Play / pause" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { description = "Media: Play / pause" })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { description = "Media: Next track" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { description = "Media: Previous track" })

-- Screenshot
hl.bind("CTRL + SHIFT + S", hl.dsp.exec_cmd("qs ipc call screenshot area"), { description = "Screenshot: Select an area" })
hl.bind("Print", hl.dsp.exec_cmd("qs ipc call screenshot screen"), { description = "Screenshot: Whole screen" })

-- Keybinds
hl.bind(mainMod .. " + return", hl.dsp.exec_cmd(terminal), { description = "Apps: Terminal" })
hl.bind(mainMod .. " + C", hl.dsp.window.close(), { description = "Windows: Close" })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), { description = "Apps: File manager" })
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("firefox"), { description = "Apps: Firefox" })
hl.bind(mainMod .. " + P", hl.dsp.window.float({ action = "toggle" }), { description = "Windows: Toggle floating" })
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("qs ipc call launcher toggle"), { description = "Shell: Launcher (=calc, >actions)" })
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("qs ipc call overview toggle"), { description = "Shell: Overview" })
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("qs ipc call launcher clipboard"), { description = "Shell: Clipboard history" })
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen(), { description = "Windows: Fullscreen" })

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

hl.bind(mainMod .. " + SHIFT + F", toggle_workspace_float, { description = "Windows: Float whole workspace" })
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.window.pseudo(), { description = "Windows: Pseudo-tile" })
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("hyprlock"), { description = "Session: Lock" })
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("qs ipc call wallpicker toggle"), { description = "Shell: Wallpaper picker" })

-- Gaming Mode: switch to Steam Big Picture in Gamescope (Deck Mode).
-- Return with Super+Shift+R inside Gaming Mode (evdev monitor) or
-- Steam > Power > Exit to Desktop.
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("/usr/local/bin/switch-to-gaming"), { description = "Session: Gaming Mode (Steam)" })

-- Move focus (mainMod) / move window (mainMod + SHIFT) with arrow keys
for key, dir in pairs({ left = "l", right = "r", up = "u", down = "d" }) do
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = dir }), { description = "Windows: Focus " .. key })
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }), { description = "Windows: Move " .. key })
end

-- Switch to (mainMod) / move window to (mainMod + SHIFT) workspaces 1..5,
-- mapped onto keys 6 7 8 9 0
for i, key in ipairs({ "6", "7", "8", "9", "0" }) do
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }), { description = "Workspaces: Go to workspace " .. i })
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Workspaces: Move window to workspace " .. i })
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.workspace.toggle_special("magic"), { description = "Workspaces: Toggle the scratchpad" })
hl.bind("ALT + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), { description = "Workspaces: Move window to the scratchpad" })

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Workspaces: Next workspace" })
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), { description = "Workspaces: Previous workspace" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Windows: Drag to move" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Windows: Drag to resize" })

-- Native scratchpad keybinds
hl.bind("ALT + M", hl.dsp.workspace.toggle_special("spotify"), { description = "Workspaces: Toggle Spotify" })
hl.bind("ALT + return", hl.dsp.workspace.toggle_special("term"), { description = "Workspaces: Toggle the terminal scratchpad" })

-- New binds added by the DE upgrade (SPEC §4.2); the lines above stay exactly as they were,
-- apart from their description labels (the cheatsheet, SPEC 5.2) and Super+V (SPEC 5.1).
-- Double-tap Super (pressed and released alone) toggles the pill / fullscreen peek.
-- Hyprland has no double-tap bind, so count taps here: only a real double-tap spawns qs.
local super_tap = { pending = false, seq = 0 }
hl.bind("SUPER + SUPER_L", function()
	if super_tap.pending then
		super_tap.pending = false
		hl.exec_cmd("qs ipc call pill peek")
		return
	end
	super_tap.pending = true
	super_tap.seq = super_tap.seq + 1
	local seq = super_tap.seq
	hl.timer(function()
		if super_tap.seq == seq then
			super_tap.pending = false
		end
	end, { timeout = 300, type = "oneshot" })
end, { release = true, description = "Shell: Expand the pill / peek" })

-- Super+D toggles the dashboard surface of the pill (frame layout).
hl.bind("SUPER + D", hl.dsp.exec_cmd("qs ipc call pill toggle dashboard"), { description = "Shell: Dashboard" })

-- Super+/ toggles the keybind cheatsheet (SPEC 5.2; frame layout).
hl.bind("SUPER + slash", hl.dsp.exec_cmd("qs ipc call pill toggle cheatsheet"), { description = "Shell: Keybind cheatsheet" })
