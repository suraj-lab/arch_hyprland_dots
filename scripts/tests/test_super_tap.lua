-- Offline test of the double-tap Super counter in binds.lua, against a fake `hl` API.
-- Run: lua scripts/tests/test_super_tap.lua (from the repository root).
local proxy
proxy = setmetatable({}, { __index = function() return proxy end, __call = function() return proxy end })

local binds, timers, commands = {}, {}, {}
hl = setmetatable({
	bind = function(keys, dispatcher, opts) binds[keys] = { fn = dispatcher, opts = opts or {} } end,
	timer = function(fn, opts) timers[#timers + 1] = { fn = fn, opts = opts }; return proxy end,
	exec_cmd = function(cmd) commands[#commands + 1] = cmd end,
}, { __index = function() return proxy end })

dofile(".config/hypr/modules/binds.lua")
local tap = assert(binds["SUPER + SUPER_L"], "double-tap bind missing")
assert(type(tap.fn) == "function" and tap.opts.release == true, "must be a release bind with a Lua function")

local function fire_timers()
	local pending = timers; timers = {}
	for _, t in ipairs(pending) do
		assert(t.opts.type == "oneshot" and t.opts.timeout == 300, "300 ms oneshot window")
		t.fn()
	end
end

tap.fn(); fire_timers()                -- single tap, window expires
assert(#commands == 0, "a single tap must do nothing")

tap.fn(); tap.fn()                     -- double tap inside the window
assert(#commands == 1 and commands[1] == "qs ipc call pill peek", "double tap peeks once")
fire_timers()                          -- the old window expiring must not break the next tap

tap.fn(); fire_timers(); tap.fn()      -- two taps with the window expired in between
assert(#commands == 1, "taps further apart than the window are not a double tap")
fire_timers()

tap.fn(); tap.fn(); tap.fn()           -- triple tap: one peek, third tap starts a new window
assert(#commands == 2, "triple tap peeks once")
tap.fn()                               -- ...which the fourth tap completes
assert(#commands == 3, "fourth tap completes the second double tap")
fire_timers()
print("PASS: double-tap Super counter (single, double, slow, triple/quadruple taps)")
