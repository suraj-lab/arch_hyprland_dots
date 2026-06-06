-- Hyprland Lua config
-- Each require() runs in its own scope; an error in one module does not
-- stop the others from loading. Order is load order.

require("modules.monitors")
require("modules.env")
require("modules.autostart")
require("modules.wallpaper")
require("modules.xdg_portal")
require("modules.options")
require("modules.animations")
require("modules.devices")
require("modules.binds")
require("modules.rules")
