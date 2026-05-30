local M = {}

local wallpaper_dir = os.getenv("HOME") .. "/.config/hypr/wallpapers"
local interval_ms = 30 * 60 * 1000
local outputs = { "DP-2", "HDMI-A-1" }
local transitions = { "fade", "left", "right", "top", "bottom", "wipe", "grow", "center", "outer", "wave" }

math.randomseed(os.time())

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function list_wallpapers()
	local files = {}
	local handle = io.popen("find " .. shell_quote(wallpaper_dir) .. " -type f 2>/dev/null")

	if handle == nil then
		return files
	end

	for file in handle:lines() do
		table.insert(files, file)
	end

	handle:close()
	return files
end

local function set_random_wallpaper(output)
	local files = list_wallpapers()

	if #files == 0 then
		return
	end

	local image = files[math.random(#files)]
	local transition = transitions[math.random(#transitions)]

	hl.exec_cmd(
		"awww img"
			.. " --outputs "
			.. shell_quote(output)
			.. " --transition-type "
			.. transition
			.. " --transition-pos center"
			.. " --transition-duration 1"
			.. " --transition-fps 144"
			.. " --transition-step 3"
			.. " "
			.. shell_quote(image)
	)
end

local function rotate_all_wallpapers()
	for _, output in ipairs(outputs) do
		set_random_wallpaper(output)
	end
end

hl.on("hyprland.start", function()
	rotate_all_wallpapers()
end)

M.timer = hl.timer(rotate_all_wallpapers, { timeout = interval_ms, type = "repeat" })

return M
