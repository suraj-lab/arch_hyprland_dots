---
name: hyprland
description: Hyprland Lua config, IPC, layer rules, keybinds, monitors, and desktop debugging
---

# Hyprland Skill

## Important — Wiki Is Source of Truth
Hyprland 0.55+ uses Lua for the main config. The Lua API is new and moving fast.
Before writing or changing `hyprland.lua`, fetch/read the relevant current Hyprland wiki page and follow it exactly.
Do not rely on old hyprlang memory, stale examples, or this skill alone for exact syntax.

Current wiki pages to verify first:

- Start / config file: https://wiki.hypr.land/Configuring/Start/
- Variables / `hl.config`: https://wiki.hypr.land/Configuring/Basics/Variables/
- Monitors / `hl.monitor`: https://wiki.hypr.land/Configuring/Basics/Monitors/
- Binds / `hl.bind`: https://wiki.hypr.land/Configuring/Basics/Binds/
- Dispatchers / `hl.dsp.*`: https://wiki.hypr.land/Configuring/Basics/Dispatchers/
- Window + layer rules: https://wiki.hypr.land/Configuring/Basics/Window-Rules/
- Workspace rules: https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
- Autostart: https://wiki.hypr.land/Configuring/Basics/Autostart/
- Animations: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
- Devices: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/
- Gestures: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
- Expanding functionality / events / timers: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Expanding-functionality/
- Dwindle layout: https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/
- Master layout: https://wiki.hypr.land/Configuring/Layouts/Master-Layout/

## Current Local State
- Active main config: `~/.config/hypr/hyprland.lua`
- Legacy fallback copy still present: `~/.config/hypr/hyprland.conf`
- Lock config: `~/.config/hypr/hyprlock.conf`
- Lua-LS config for nvim: `~/.config/hypr/.luarc.json`
  - Loads Hyprland stubs from `/usr/share/hypr/stubs`
  - Marks `hl` as a known global
- Quickshell autostart is in `hyprland.lua` under `hl.on("hyprland.start", function() ... end)`.
- Lua modules are loaded from `~/.config/hypr/modules/` via `require("modules.<name>")`.
  - `modules.wallpaper` rotates awww wallpapers for `DP-2` and `HDMI-A-1` every 30 minutes.
  - `modules.xdg_portal` restarts xdg-desktop-portal helpers on Hyprland start.
- Quickshell was rebuilt/reinstalled locally against Qt 6.11.1 on 2026-05-25 to clear the Qt mismatch warning.
- Apple Magic Trackpad over USB is configured per-device as `apple-inc.-magic-trackpad` and `apple-inc.-magic-trackpad-1`.

Important config selection behavior:
- If `~/.config/hypr/hyprland.lua` exists, Hyprland uses it and ignores `hyprland.conf`.
- Hyprland does **not** automatically fall back to `.conf` if the Lua config has an error.
- To revert to legacy config, rename/remove `hyprland.lua` and restart the Hyprland session.

## Lua Config Basics
Use Hyprland's injected global `hl` namespace.

```lua
hl.config({
  general = {
    gaps_in = 7,
    gaps_out = 11,
    border_size = 2,
    layout = "dwindle",
  },
  input = {
    kb_layout = "gb",
    touchpad = {
      natural_scroll = false,
    },
  },
})
```

Multiple `hl.config()` calls are allowed; they merge/update the passed values.

Use `require()` to split config files if needed. The wiki notes each `require()` gets separate Lua scope, so an error in one required file does not stop the others.

Local module pattern:

```lua
require("modules.wallpaper")
require("modules.xdg_portal")
```

Resolve relative module paths from `~/.config/hypr/hyprland.lua`, e.g. `require("modules.wallpaper")` loads `~/.config/hypr/modules/wallpaper.lua`.

## Current Lua Patterns

### Monitors
```lua
hl.monitor({ output = "DP-2", mode = "preferred", position = "1920x-400", scale = 1, vrr = 2, bitdepth = 10, cm = "hdr" })
hl.monitor({ output = "desc:ViewSonic Corporation VX2476 Series UPA213310203", mode = "1920x1080@74", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-4", disabled = true })
```

### Autostart
The old `exec-once` maps to the `hyprland.start` event.

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("quickshell")
  hl.exec_cmd("awww-daemon")
end)
```

`hl.exec_cmd()` is asynchronous; no trailing `&` should be needed.

### Environment
```lua
hl.env("XCURSOR_SIZE", "24")
hl.env("GTK_THEME", "Adwaita:dark")
```

### Binds
```lua
local mainMod = "SUPER"

hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("qs msg launcher toggle"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + P", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.window.pseudo())
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("hyprlock"))
```

Mouse movement binds use normal `hl.bind()` with `{ mouse = true }`:

```lua
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
```

### Dispatcher mappings currently used
- `exec, cmd` → `hl.dsp.exec_cmd("cmd")`
- `killactive` → `hl.dsp.window.close()`
- `fullscreen` → `hl.dsp.window.fullscreen()`
- `togglefloating` → `hl.dsp.window.float({ action = "toggle" })`
- `pseudo` → `hl.dsp.window.pseudo()`
- `movefocus, l/r/u/d` → `hl.dsp.focus({ direction = "l" })`
- `workspace, 1` → `hl.dsp.focus({ workspace = 1 })`
- `workspace, e+1` → `hl.dsp.focus({ workspace = "e+1" })`
- `movetoworkspace, 1` → `hl.dsp.window.move({ workspace = 1 })`
- `movewindow, l/r/u/d` → `hl.dsp.window.move({ direction = "l" })`
- `bindm ..., movewindow` → `hl.dsp.window.drag()` with `{ mouse = true }`
- `bindm ..., resizewindow` → `hl.dsp.window.resize()` with `{ mouse = true }`
- `togglespecialworkspace, name` → `hl.dsp.workspace.toggle_special("name")`

### Window rules
```lua
hl.window_rule({ match = { class = "Spotify" }, workspace = "special:spotify silent" })
hl.window_rule({ match = { class = "Spotify" }, float = true })
hl.window_rule({ match = { class = "Spotify" }, size = { "75%", "65%" } })
hl.window_rule({ match = { class = "Spotify" }, center = true })
```

Rules are evaluated top-to-bottom; preserve order when converting.

### Layer rules
Layer rules live on the Window Rules wiki page in current Lua docs.

```lua
hl.layer_rule({ match = { namespace = "quickshell" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell" }, blur_popups = true })
hl.layer_rule({ match = { namespace = "quickshell" }, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-launcher" }, animation = "none" })
hl.layer_rule({ match = { namespace = "quickshell-launcher" }, blur = false })
```

### Animations / curves
Verify syntax on the Animations wiki before changing. Current Lua docs use `bezier = "name"` or `spring = "name"` on animations.

Animation tree highlights:
- `windows`, `windowsIn`, `windowsOut`, `windowsMove` support `slide`, `popin`, `gnomed`.
- `layers`, `layersIn`, `layersOut` support `slide`, `popin`, `fade`.
- `workspaces` supports `slide`, `slidevert`, `fade`, `slidefade`, `slidefadevert`.
- `fadeSwitch` controls active-window / opacity transition smoothness.
- Avoid `borderangle` style `loop` unless the user accepts continuous GPU/CPU rendering.

Current preferred local preset is macOS-like snappy motion with smoother focus fading:

```lua
hl.curve("macSpring", { type = "spring", mass = 1, stiffness = 95, dampening = 18 })
hl.curve("macSoftSpring", { type = "spring", mass = 1, stiffness = 75, dampening = 16 })
hl.curve("snappyOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("smoothFocus", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.0, spring = "macSpring", style = "popin 85%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.4, bezier = "snappyOut", style = "popin 88%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.4, spring = "macSpring" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.2, spring = "macSoftSpring", style = "slidefade 18%" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 6, bezier = "smoothFocus" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 6, bezier = "smoothFocus" })
```

### Per-device config
```lua
hl.device({
  name = "epic-mouse-v1",
  sensitivity = -0.5,
})
```

Apple Magic Trackpad over USB currently appears as two pointer devices. Configure both names if keeping wired mode:

```lua
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
```

Trackpad gestures use the new `hl.gesture()` API, not old `workspace_swipe_fingers`:

```lua
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
```

Bluetooth note: user chose **not** to pair the Apple Trackpad over Bluetooth because it may interfere with Hackintosh/MacBook pairing. Wired USB is preferred.

## Lua Modules / Script Migration Notes

### Wallpaper rotation via `modules.wallpaper`
The old bash scripts `~/.config/hypr/scripts/awww-random-DP2` and `awww-random-HDMI1` were replaced by `~/.config/hypr/modules/wallpaper.lua`.

Important: verify `awww img --help` when changing flags. Current documented local CLI shape:

```bash
awww img --outputs DP-2 \
  --transition-type fade \
  --transition-pos center \
  --transition-duration 1 \
  --transition-fps 144 \
  --transition-step 3 \
  /path/to/image
```

Valid transition types from local `awww img --help` include:
`none`, `simple`, `fade`, `left`, `right`, `top`, `bottom`, `wipe`, `wave`, `grow`, `center`, `any`, `outer`, `random`.

The module uses `hl.timer()` instead of infinite bash `while true` loops:

```lua
M.timer = hl.timer(rotate_all_wallpapers, { timeout = 30 * 60 * 1000, type = "repeat" })
```

### xdg portal module
`~/.config/hypr/modules/xdg_portal.lua` replaces `~/.config/hypr/scripts/xdg-portal-hyprland`.

Local path correction discovered on this system:
- Correct: `/usr/lib/xdg-desktop-portal-hyprland`
- Incorrect/missing: `/usr/libexec/xdg-desktop-portal-hyprland`

Be careful when composing async shell commands: `cmd &; sleep 2` is invalid. Use `cmd & sleep 2` or wrap with `sh -c` and validate with `sh -n`.

## IPC via Quickshell
```qml
import Quickshell.Hyprland

Hyprland.dispatch("workspace 3")
Hyprland.dispatch("exec [float;size 40% 90%] pavucontrol")
Hyprland.focusedMonitor.name     // current focused monitor name
Hyprland.workspaces.values       // all workspaces
```

## Quickshell / Layer Namespace Notes
Give each overlay a unique `WlrLayershell.namespace` so layer rules can target it independently without affecting the bar.

Current namespaces include:
- `quickshell`
- `quickshell-launcher`
- `quickshell-wallpicker`
- `quickshell-session`
- `quickshell-screenshot`
- `quickshell-overview`

## Useful CLI
```bash
hyprctl monitors              # current monitor state
hyprctl activewindow          # focused window
hyprctl clients -j            # all windows as JSON
hyprctl workspaces            # workspace list
hyprctl -j activeworkspace    # current workspace JSON
hyprctl reload                # reload current config
hyprctl configerrors          # show config/runtime config errors
hyprctl instances             # active Hyprland instances
hyprctl devices -j            # input devices; use for per-device names
```

Check Apple trackpad live state:

```bash
hyprctl devices | grep -i -A5 -B2 'apple\|magic\|trackpad'
```

## Config Editing Workflow
1. Read the relevant wiki page first.
2. Edit `~/.config/hypr/hyprland.lua` minimally.
3. Validate Lua syntax if possible:
   ```bash
   luac -p ~/.config/hypr/hyprland.lua
   ```
4. Reload and check errors:
   ```bash
   hyprctl reload && hyprctl configerrors
   ```
5. For module or generated shell command changes, also validate relevant helper syntax when possible:
   ```bash
   luac -p ~/.config/hypr/hyprland.lua ~/.config/hypr/modules/*.lua
   printf '%s\n' '<generated shell command>' | sh -n
   ```
6. If nvim shows `undefined global 'hl'`, check `~/.config/hypr/.luarc.json` and `/usr/share/hypr/stubs/hl.meta.lua`.

## Troubleshooting Current Setup
- If Quickshell does not appear after login:
  - Check `pgrep -a quickshell`
  - Check `qs log`
  - Check `hyprctl configerrors`
  - Verify the `hl.on("hyprland.start", ...)` block still contains `hl.exec_cmd("quickshell")`
- If `qs log` says Quickshell was built against an older Qt, rebuild/reinstall Quickshell against current Qt packages.
- If autostart entries other than Quickshell are running, the Hyprland Lua autostart block likely fired; debug Quickshell itself or startup timing.
- If wallpapers do not rotate:
  - Check `pgrep -a awww-daemon`.
  - Run `awww img --help` before changing module flags.
  - Confirm outputs with `hyprctl monitors` (`DP-2`, `HDMI-A-1` currently expected).
- If xdg portals fail after login:
  - Verify `/usr/lib/xdg-desktop-portal-hyprland` exists.
  - Check portal processes with `pgrep -af xdg-desktop-portal`.
  - Check logs with `journalctl --user -b | grep -i portal`.

## Safety Notes
- Do not add clever/programmatic Lua behavior during migration unless the user asks. First priority is faithful `hyprland.conf` → `hyprland.lua` parity.
- Keep `hyprland.conf` untouched as a rollback reference until the Lua config is proven stable.
- For monitor/disk/boot-related operations, follow the global safety rules and verify live state first.
