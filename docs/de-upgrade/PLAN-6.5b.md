# Implementation plan: Phase 6.5b (Settings: Sound, Displays, Network/Bluetooth, Default apps, Gaming)

Hand-off plan for an implementing model. Read this whole file, then `docs/de-upgrade/SPEC.md`
section **6.5** and the latest change-log entry (6.5a), before writing code.

Repo: `~/Projects/Dotfiles/arch_hyprland_dots`, branch `feat/de-shell` (local, unpushed).
Starting point: the commit that adds this file, on top of `8bdb796` (6.5a) and the phase4
`xvfb-run` harness fix. Working tree must be clean before you start; if it is not, stop and ask.

## 0. Ground rules (non-negotiable)

- **Do not commit or push.** When done, show `git status`/`git diff --stat`, propose a commit
  message in the house style (see `git log -5`), and wait for Suraj.
- **Frozen, do not touch:** `deploy/gaming/`, `.config/environment.d/99-gaming-session.conf`,
  `.config/gamescope/`, `scripts/install-gaming-mode.sh`, `docs/gaming-mode.md`,
  `packages/gaming-mode.txt`, `packages/daily-apps.txt`, `.config/hypr/modules/binds.lua`
  (no bind changes at all in 6.5b), and `.config/hypr/modules/monitors.lua`.
- **No sudo, no package installs.** Everything needed is installed: `xdg-mime` (xdg-utils),
  `gamemoded`, `hyprctl`, Quickshell 0.3.1.
- **Do not write the repo's `.config/mimeapps.list`.** The live `~/.config/mimeapps.list` is a
  regular file (a bootstrap copy that apps add URL handlers to at runtime). The shell edits
  only the live file.
- Minimal diffs, existing style. No new abstractions for one caller. `ponytail:` comment on
  any deliberate shortcut with a known ceiling.
- Tools: `/usr/lib/qt6/bin/qmllint`, `/usr/lib/qt6/bin/qmlformat` (format check only, do not
  rewrite files with it), `rg --hidden`.
- Edit-tool gotchas seen in this repo: avoid the em-dash character in Edit `oldText`
  (use Python `str.replace` for those lines); never put `//` comments mid-line inside a
  one-line object literal in `scripts/tests/frame-shell.qml`.

## 1. What already exists (reuse, do not re-implement)

| Need | Use |
|---|---|
| Settings surface, section list, row layout | `components/pill/surfaces/SettingsPanel.qml`: `sections` array, `Setting { title; hint; <control> }`, `Heading`, `ClockStepper`; each section is a `ColumnLayout { visible: root.section === "<key>" }` inside `flick`/`content` |
| Segmented choice | `SurfaceChoice.qml` (`objectName` + `choice:<label>` children; see how `lockSec` uses it) |
| Buttons / icons / switches | `SurfaceButton.qml`, `SurfaceIcon.qml`, `SurfaceSwitch.qml` |
| Switch to another surface | `root.surfaceRequested("network" \| "bluetooth" \| "sound")`, already wired in `PillOverlay.qml` to `openSurface(name, false)` |
| Run an action after closing | `root.actionRequested(id)` (e.g. `"wallpaper"`) → `PillOverlay.runAction` → `shell.qml runShellAction` |
| Persisted settings | `Config.set("a.b", value)` (writes settings.json, keeps unknown keys, refuses on a malformed file). Add validated readers to `services/Config.qml` like `nightLight` |
| Sound devices | `Audio.sinks`, `Audio.sources` (entries `{name, desc, index, state, isDefault}`), `Audio.setDefaultSink(name)`, `Audio.setDefaultSource(name)` (sets `Pipewire.preferredDefaultAudio*`; WirePlumber persists it, not settings.json) |
| Wi-Fi / BT status | `Net.wifiEnabled`, `Net.ssid`; `Bt.enabled`, `Bt.devices` (entries have `connected`) |
| Desktop Game Mode | `services/Desktop.qml`: `gameModeOverride`, `gamemodedActive`, `desiredGameMode` binding, `toggleGameMode()` |
| One-shot command pattern | the `about` `Process` in SettingsPanel (`onActiveChanged` starts it; `StdioCollector`) |
| App names/icons from a desktop id | `DesktopEntries.byId(id)` (Quickshell; `id` is the file name without `.desktop`; returns null if unknown). `DesktopEntry` exposes **no MIME types**, so candidates come from `mimeinfo.cache` (below) |

## 2. Sections to add

Final `sections` order: Appearance, Displays, Sound, Network & Bluetooth, Power & idle, Night
light, Default apps, Gaming, Keybinds, About. Keys: `displays`, `sound`, `connections`,
`defaults`, `gaming`. Nerd Font glyphs **must exist in JetBrainsMono Nerd Font** (6.5a hit
`\uf53f` rendering as tofu). Known-good in this repo: `\uf108` desktop, `\uf028` volume,
`\uf1eb` wifi, `\uf1de` sliders, `\uf11b` gamepad. Verify each in the render preview.

With 10 sections the left list must still fit 560 px tall; check it in the render (§5.3). If it
does not fit, reduce the entry height/spacing, do not add scrolling to the list.

### 2.1 Displays (read-only)

- On section open (and each re-open), run `hyprctl monitors -j` in a `Process`. Parse with a
  **pure, unit-tested** function `parseMonitors(text)` returning
  `[{name, description, mode: "3440x1440 @ 165 Hz", scale, position: "1920, -400", vrr, focused}]`,
  sorted by x then y; `[]` on invalid JSON (never throw). Refresh rate: round to integer Hz.
  Hyprland's `vrr` field is a boolean; show "VRR on/off".
- One card/row per monitor: name + description (elide), mode, scale, position, VRR.
- Hint text under the list: "Edit hypr/modules/monitors.lua to change the layout."
- **No "Open nwg-displays" button** (deliberate SPEC deviation, Suraj's call: he doesn't use
  it, and it could not save here anyway: it writes hyprland.conf-syntax `monitors.conf`, while
  this config is Lua and loads no `.conf`). Record the deviation in the SPEC change-log entry.
- Never write any monitor config from the shell (SPEC out-of-scope list).

### 2.2 Sound

- Two groups, **Output** and **Input**, listing `Audio.sinks` / `Audio.sources` as selectable
  rows (radio-style: accent dot on `isDefault`). Click → `Audio.setDefaultSink(name)` /
  `setDefaultSource(name)`. Label = `desc`.
- Rows `objectName: "sink:" + name` / `"source:" + name` for tests.
- Empty state: "No audio devices" (this is what the Xvfb sandbox shows; there is no PipeWire).
- A **"Volume and apps..."** link → `root.surfaceRequested("sound")`.
- No settings.json key: WirePlumber persists the default device. Say so in the hint.

### 2.3 Network & Bluetooth (links)

- Two rows. Wi-Fi: status (`Net.wifiEnabled ? (Net.ssid || "Not connected") : "Off"`) and a
  button → `surfaceRequested("network")`. Bluetooth: `Bt.enabled ? (<n> connected) : "Off"`
  and a button → `surfaceRequested("bluetooth")`. `objectName`s `openNetwork`, `openBluetooth`.

### 2.4 Default apps

Categories (constant table in SettingsPanel). The **first** type is the one queried and the
one whose candidates are offered; setting a category writes **all** its types in one call:

| Category | Types |
|---|---|
| Web browser | `x-scheme-handler/https`, `x-scheme-handler/http`, `text/html`, `application/xhtml+xml` |
| Files | `inode/directory` |
| Text editor | `text/plain`, `text/markdown`, `text/x-python`, `text/x-csrc`, `text/x-chdr`, `text/x-lua`, `application/x-shellscript`, `application/json`, `application/xml`, `application/toml`, `application/x-yaml` |
| Images | `image/png`, `image/jpeg`, `image/gif`, `image/bmp`, `image/tiff`, `image/svg+xml` |
| Terminal | read-only, see **Decision D2** |

(Types mirror the repo's `.config/mimeapps.list`; `application/pdf` stays with the browser file
entry and is deliberately not touched.)

- **Current default:** `xdg-mime query default <firstType>` per category (one `Process` per
  query, run sequentially or in a single `sh -c` that prints `type=value` lines; parse with a pure
  function). Empty output = "Not set".
- **Candidates:** union of desktop ids listed for the first type in every
  `applications/mimeinfo.cache` under `${XDG_DATA_HOME:-$HOME/.local/share}` and each dir of
  `${XDG_DATA_DIRS:-/usr/local/share:/usr/share}` (lines `type=a.desktop;b.desktop;`). Read them
  with one `sh -c` that `cat`s the files `2>/dev/null`; parse with a pure function
  `candidates(cacheText, type)` (dedupe, keep order). Always include the current default even if
  absent from the caches. Drop ids for which `DesktopEntries.byId(id without .desktop)` is null
  **or** has `noDisplay` (check the property name in quickshell-core.qmltypes before using it;
  if it does not exist, skip that filter).
- **Control:** a compact dropdown-like chooser: the current app (icon + name) as a button;
  clicking expands an inline list of candidates below the row (no popup windows, no
  `ComboBox`: surfaces have no popup parent). Selecting runs
  `xdg-mime default <id> <all types...>` then re-queries. `objectName`s:
  `default:<key>` for the button and `candidate:<id>` for list rows.
- **Why xdg-mime:** verified on this machine (XDG_CURRENT_DESKTOP=Hyprland → generic backend):
  `xdg-mime default thunar.desktop text/html x-scheme-handler/http` replaces the key in
  `[Default Applications]` in place, appends missing keys, and keeps comments, other keys and
  other sections (`[Added Associations]`). Do not hand-write an INI editor.
- On `xdg-mime` failure (non-zero exit), show its stderr under the row, as the devices surface
  does.

### 2.5 Gaming

- **Status rows (read-only), refreshed on section open** via one `sh -c`:
  - Gaming Mode helper: `test -x /usr/local/bin/switch-to-gaming`
  - GameMode daemon: `command -v gamemoded`
  - GameMode active now: `Desktop.gamemodedActive` (already live, no command)
  Each shows a check/cross glyph + short text. Pure parser for the command output.
- **"Game Mode follows games"** switch (SPEC: "the Desktop Game Mode auto toggle"): new
  persisted `gaming.autoGameMode`, default **true** (current behaviour). Add
  `Config.gaming` reader: `{ autoGameMode: values.autoGameMode !== false }` (only a literal
  `false` disables; mirror how `idle.caffeine` is validated).
- In `Desktop.qml`, turn the `desiredGameMode` binding into a call of a pure, testable
  function, e.g. `wantGameMode(override, auto, active)`:
  `override === "on" || (override !== "off" && auto && active)`, bound with
  `Config.gaming.autoGameMode`. Manual toggle behaviour (`toggleGameMode`) must not change.
- Button **"Enter Gaming Mode"**: do **not** add one (not in SPEC; the key bind and launcher
  entry already exist).

## 3. Decision for Suraj (implement the default; list it in the final report)

- **D2, terminal has no MIME default.** The terminal is `ghostty`, hardcoded in
  `binds.lua` (`local terminal = "ghostty"`, frozen), `services/Net.qml` and
  `services/Updates.qml`; `xdg-terminal-exec` is not installed. Default: a read-only row
  "Terminal: Ghostty (set in hypr binds)". Do not add a setting.

## 4. Files expected to change

- `components/pill/surfaces/SettingsPanel.qml`: new sections, pure helpers, processes.
  If it grows past ~700 lines, move **only** the Default apps section into a new
  `surfaces/SettingsDefaults.qml`; otherwise keep one file.
- `services/Config.qml`: `gaming` reader.
- `services/Desktop.qml`: `wantGameMode()` + binding.
- `components/pill/surfaces/Launcher.qml`: update the `settings` action subtitle
  (currently "Appearance, power, night light").
- Tests: `scripts/tests/test_shell_services.js`, `scripts/check-desktop-phase4.py`,
  possibly `scripts/tests/frame-shell.qml`, and `scripts/check-desktop-phase3.py` if the
  `CONFIG` line gains `gaming` (it currently prints only `idle` and `weather`; leave that alone).
- `docs/de-upgrade/SPEC.md`: change-log entry (Python insert after `## Change log`, match the
  6.5a entry's style; mark "deployed; not yet committed").
- **Not** `shell.qml`, `PillOverlay.qml`, `Theme.qml` unless a real need appears.

## 5. Tests (all must pass before deploy)

### 5.1 Unit (`node scripts/tests/test_shell_services.js`)

The loader (`load(file, names)`) extracts `function name(...) {` by regex and needs **exactly
one space before `{`**. Add one `PASS:` line covering:
- `parseMonitors`: the two real monitors below, invalid JSON → `[]`, sort order, 164.89999 → 165 Hz.
- default-app parsers: `xdg-mime` query output, `candidates()` with duplicates across two
  caches, a missing type, current default injected when absent.
- gaming status parser; `wantGameMode` truth table (on/off/auto × auto flag × active).

Real monitors on this host (fixture):
`DP-2 3440x1440@164.89999 scale 1 vrr false pos 1920,-400 "Dell Inc. AW3423DWF 70742S3"`,
`HDMI-A-1 1920x1080@74.973 scale 1 vrr false pos 0,0 "ViewSonic Corporation VX2476 Series UPA213310203"`.

### 5.2 Integration (`python3 scripts/check-desktop-phase4.py`)

Private Xvfb, fake `$HOME`, command stubs in a dict near the top (see `"hyprctl"`,
`"udisksctl"`, `"thunar"`). Required stub changes:
- `hyprctl`: currently answers only `binds -j`; add `monitors -j` → `cat "$HOME/monitors.json"`
  (write the fixture). Keep `exit 1` for everything else.
- `xdg-mime`: `query default <t>` answers from a fake file (e.g. `$HOME/mime-defaults`,
  `type=id` lines); `default <id> <types...>` appends `$*` to `$HOME/xdg-mime-calls` and
  updates the fake file so the re-query shows the change.
- Candidates: put a fixture `mimeinfo.cache` in the fake `$HOME/.local/share/applications/`.
  Do **not** override `XDG_DATA_DIRS` (the launcher tests use the real app list). Assert the
  fixture ids appear, not an exact list. Fixture ids must resolve via `DesktopEntries.byId`, so
  either use ids that exist on this host (`firefox`, `thunar`, `codium`, `viewnior`) or add
  minimal `.desktop` files to the fake `$HOME/.local/share/applications/`.

Add a block after the existing `# ---- 6.5a settings` block, reusing `click_at(path, what)`
(which resolves `ipc("where", "a/b")` object-name paths in the open tier) and `wait_settings`:
- Displays: both monitors listed with the expected text (expose via a small status field or
  check via `where` visibility); no nwg-displays button exists.
- Sound: the empty state is shown; "Volume and apps..." opens the `sound` surface.
- Network & Bluetooth: each button opens its surface.
- Default apps: click `default:browser` → `candidate:<id>` → `xdg-mime-calls` contains exactly
  `default <id> x-scheme-handler/https x-scheme-handler/http text/html application/xhtml+xml`,
  and the row shows the new app after re-query.
- Gaming: click the switch → `gaming.autoGameMode` is `false` in settings.json, unknown keys
  kept; click again → `true`.
- Restart persistence (SPEC check): after the gaming switch is off, restart the sandbox shell
  (see how the file restarts it elsewhere, or `qs kill` + relaunch the test instance) and
  assert the switch still shows off. If a restart helper doesn't exist, report that instead
  of building a large one.
- Extend the 6.5a `PASS:` print lines.

**Do not revert the harness's `xvfb-run -a` display startup** (Suraj's fix, 2026-09-27): the
old `Xvfb -displayfd` could take over Hyprland's X socket when its abstract socket is disabled,
which stopped Steam (Xwayland) from displaying. Never pass a fixed `-d`/display number either.
If you start any other private X server for screenshots, go through `xvfb-run -a` the same way.

Harness quirks: use `LC_ALL=C.UTF-8` (already set); pointer must be over the window before
`xdotool click`; positions animate, so always go through `click_at`/`wait_pill`; no WM, so
`activeFocus` is unreliable; after the run, `pgrep -af 'Xvfb|fake_mpris|dbus-run-session'`
must be empty.

### 5.3 Visual check

Render the Settings surface for every new section to `~/.cache/pill-preview/settings-b-<section>.png`
using the phase4 sandbox (there is prior art for screenshots in this workflow: `import -window root`
or `xwd` on the private Xvfb display). Look at each image: no tofu glyphs, controls
right-aligned, nothing clipped, section list fits.

### 5.4 Full regression

`node scripts/tests/test_shell_services.js`, `python3 scripts/check-desktop-phase0.py`,
`python3 scripts/check-desktop-phase3.py`, `python3 scripts/check-desktop-phase4.py` all exit 0,
twice for phase4 (it has timing-sensitive steps). `git diff --check` clean. `qmllint` shows no
new warnings in touched files compared with HEAD.

## 6. Live deploy (only after section 5 passes)

Follow the established procedure exactly (see the 6.5a deploy in the session history / SPEC):
1. Preflight: for every file to be copied, live `~/.config/quickshell/<f>` == `git show HEAD:...`;
   new files must not exist live. Abort on any mismatch.
2. Backup to `~/.local/state/dotfiles-backups/phase6-settings-b-<YYYYmmdd-HHMMSS>/`: `files/<f>`
   for changed files, `new-files.txt`, plus `~/.config/mimeapps.list` and `settings.json`.
3. Record `qs ipc --path ~/.config/quickshell/shell.qml call desktop status` (Caffeine is now
   persisted, so it should survive by itself; verify rather than force it).
4. `qs kill --id <instance>`, wait for the PID to exit, copy the specific files, relaunch with
   `hyprctl dispatch 'hl.dsp.exec_cmd("quickshell --daemonize --no-duplicate --path /home/suraj/.config/quickshell/shell.qml")'`.
5. Verify: IPC answers; `qs log` has no new WARN/ERROR/TypeError/ReferenceError/binding loops
   (ignore icon/qt.svg noise); live == repo for copied files; polkit agent still registered.
6. Do not change any default app live yourself. Tell Suraj what to try.

## 7. Report back to Suraj

Plain, short: what each section does, how to open it, the D2 outcome, exact live test steps (switch browser and back via Settings,
confirm `xdg-mime query default x-scheme-handler/https`; switch output device; toggle
"Game Mode follows games" and restart the shell), backup path, and the proposed commit message.
Then wait.

## 8. Done when

- All five SPEC 6.5b areas present and behaving as above (Displays without nwg-displays);
  D2 default implemented.
- Section 5 green (phase4 twice), no stray processes, diff check clean.
- Deployed live with backup; SPEC change-log entry written; nothing committed.
