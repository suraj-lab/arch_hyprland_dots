# DE Upgrade — Spec & Implementation Plan

**Repo:** `suraj-lab/arch_hyprland_dots` · **Branch:** `feat/de-shell` · **Written:** 2026-09-23
**Audience:** a coding agent working locally on Suraj's machine (Arch + CachyOS repos, Hyprland 0.56 with the Lua config, Quickshell).

Turn the Hyprland + Quickshell dotfiles into a desktop environment that feels like
KDE Plasma or Caelestia, while keeping Suraj's visual identity, his keybinds, and
his Gaming Mode exactly as they are.

---

## 0. How to use this document

1. Read §1 (hard rules) and §2 (current state) completely before touching anything.
2. Work **phase by phase** (§6). Each phase has tasks, the files to touch, and
   acceptance checks. Do not start a phase until the previous one passes its checks.
3. Prepare reviewable changes per task. **Commit only when Suraj explicitly asks**;
   use conventional-ish messages like the repo's history.
4. When the spec says **ASK**, stop and ask Suraj. Do not guess.
5. When a fact here disagrees with the live system (a package name, an API), trust
   the live system, tell Suraj, and record the correction at the bottom of this file
   under **Change log**.
6. Visual reference: `docs/de-upgrade/reference/frame-pill-mockup.dc.html` is the
   approved mockup, with numbers in its `renderVals()`. §5 restates everything you
   need, so you don't have to render it. The supplied HTML lacks `support.js`, so it
   is not a self-contained interactive preview.
7. See [PHASE0.md](PHASE0.md) for actual baseline observations, offline results,
   recovery semantics, and the pending live-deployment gate.

---

## 1. Hard rules

### 1.1 Packages: official Arch repos only
- **Every new package** must come from the official Arch repos: `core`, `extra` or
  `multilib`. **No AUR packages** and no `-git` or `-bin` builds from anywhere.
- Before adding a package, verify it:
  `pacman -Si <pkg> | awk -F': ' '/^Repository/{print $2}'` must print `core`,
  `extra` or `multilib`. CachyOS repos (`cachyos*`) do **not** count as official
  for *new* additions.
- Existing Gaming Mode packages from the CachyOS repos (`gamescope-session-cachyos`,
  `proton-cachyos-slr`, `jupiter-hw-support`, the `linux-cachyos` kernel) are **out of
  scope**. Leave them alone.
- `packages/daily-apps.txt` and `packages/gaming-mode.txt` still contain AUR apps
  (e.g. `vscodium-bin`, `cemu`, `steamtinkerlaunch`). They are **out of scope**;
  don't touch them. `paru` stays the user's AUR helper for his own apps, but
  `packages/desktop-core.txt` must become installable with plain `pacman`
  (Task 1.1).

### 1.2 Don't touch Gaming Mode
These files are **frozen**. Change them only in Phase 7, and only after Suraj
approves in writing:
- everything under `deploy/gaming/`
- `.config/environment.d/99-gaming-session.conf`
- `.config/gamescope/`
- `scripts/install-gaming-mode.sh`, `docs/gaming-mode.md`
- the `gaming-desktop-restore` line in `.config/hypr/modules/autostart.lua`
- `Super+Shift+S` (enters Gaming Mode) and `Super+Shift+R` (the evdev exit monitor
  inside gamescope)

After **every phase**, run the Gaming Mode round-trip (§7.3).

### 1.3 Keybinds stay as they are
Existing binds keep their keys and their meaning. Full table in §4. New binds are
allowed only where §4 lists them, and must not collide with an existing one
(`hyprctl binds -j` is the source of truth).

### 1.4 Hyprland is configured in Lua (0.55+)
- Config lives in `.config/hypr/hyprland.lua` + `modules/*.lua`. There is **no**
  `hyprland.conf`. Don't create one.
- **Legacy dispatcher strings are rejected.** From shell or QML, every dispatch
  must be a Lua expression:
  - `hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })'`
  - `hyprctl dispatch 'hl.dsp.exit()'`
  - `hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'`
  - `hyprctl dispatch 'hl.dsp.exec_cmd("pavucontrol", { float = true, size = { "40%", "90%" } })'`
  - Runtime config: `hyprctl eval 'hl.config({ decoration = { blur = { enabled = false } } })'`
  - In QML, `Hyprland.dispatch("<same Lua expression>")`.
- After editing any Lua file: `hyprctl reload && hyprctl configerrors` must print
  nothing.
- Reference for the Lua API: `/usr/share/hypr/stubs` (LuaLS stubs), `hyprctl repl`,
  and the Hyprland wiki. `dpms` and `force_idle` must not be bound directly; wrap
  them in `hl.timer` (see the wiki).

### 1.5 Quickshell
- Target **`quickshell` 0.3.1 from `[extra]`** (verified 2026-09-23). Every module
  this spec uses exists in 0.3.1: `Quickshell.Wayland` (`IdleMonitor`,
  `IdleInhibitor`, `WlSessionLock`), `Quickshell.Networking`,
  `Quickshell.Bluetooth`, `Quickshell.Services.Polkit`, `.Pam`, `.UPower`,
  `.Pipewire`, `.Notifications`, `.Mpris`, `.SystemTray`, and `Quickshell.Io`
  (`FileView`, `JsonAdapter`, `Process`, `IpcHandler`).
- Docs: https://quickshell.org/docs/ — use the page for the installed version.
- Run and debug with `qs -c <config> --log-rules '*.debug=false'`, or plain `qs`
  (the config is `~/.config/quickshell/shell.qml`). There must be **no QML errors**
  in the log at the end of each phase.
- Prefer native Quickshell services over polling shell commands (`nmcli`,
  `bluetoothctl`, `pgrep` loops).

### 1.6 General
- Don't run `sudo` or anything that changes system state (enabling system units,
  editing `/etc`) without **ASK**ing. Repository edits are allowed; deployment to
  live `~/.config`, package changes and disruptive user-service/session actions
  require separate approval.
- Never delete a working feature before its replacement is in and tested.
- Keep the bootstrap working: `scripts/bootstrap-arch.sh --dry-run` must still
  succeed at the end of every phase that touches packages or deploy steps.

---

## 2. Current state (as of this branch)

### 2.1 Layout
```
.config/hypr/hyprland.lua            requires modules in order
.config/hypr/modules/{monitors,env,autostart,wallpaper,xdg_portal,options,animations,devices,binds,rules}.lua
.config/hypr/hyprlock.conf           regenerated by quickshell/scripts/extract-accent.sh (accent-coloured)
.config/quickshell/shell.qml         ShellRoot: bar per screen, overlays, notification server, IPC
.config/quickshell/theme/Theme.qml   design tokens (singleton)
.config/quickshell/components/       Bar chips, UnifiedPanel (Sound/Notifs/System tabs), AppLauncher,
                                     WallpaperPicker, Overview, ScreenshotOverlay, OSD, NotificationToasts,
                                     SessionMenu (unused), ScreenTimeTracker, DesktopServices (new)
.config/quickshell/scripts/          extract-accent.sh, random-wallpaper.sh, desktop-gamemode.py (new)
packages/*.txt                       manifests used by scripts/bootstrap-arch.sh
deploy/gaming/                       FROZEN (§1.2)
```

### 2.2 Phase 0 work (based on supplied patch `9ffbff3`; deployed, not committed)
- Legacy Hyprland dispatch strings rewritten to Lua (`Workspaces.qml`, `Overview.qml`,
  `SystemView.qml` Wi-Fi and mixer launchers, logout in `shell.qml`,
  `SessionMenu.qml`, `.config/wlogout/config`).
- `components/DesktopServices.qml`:
  - Idle chain via `IdleMonitor`: lock at 600 s, DPMS at 900 s, suspend off. Inhibitors
    are respected.
  - Caffeine (`IdleInhibitor` on the bar window).
  - Night light, still using `wlsunset` — **must move to `hyprsunset`** (Task 2.6).
  - Desktop Game Mode: automatically on while `gamemoded -s` reports "is active".
    It runs `scripts/desktop-gamemode.py on <current-dnd>`, which saves the prior
    compositor/DND state, turns off blur and animations and sets `inactive_opacity = 1.0`.
    DND/chip state changes follow acknowledgement. An `off` restores the snapshot;
    startup reconciles saved state from the same compositor session.
  - IPC target `desktop`: `toggleCaffeine`, `toggleNightLight`, `toggleGameMode`,
    `enterGamingMode`, `status`.
- System tab: tiles for Caffeine, Night Light, Game Mode and Enter Gaming Mode, plus an
  "Idle" status row.
- Bar chips: `Caffeine.qml` and `GameMode.qml` (the GameMode chip used to grep for a
  string gamemoded never prints, so it never showed).
- Session overlay: a sixth "Gaming" button that runs `/usr/local/bin/switch-to-gaming`.
- The unused `runShellAction(id)` patch scaffold is deferred until Phase 5 has a caller.
- Approved live deployment/startup/IPC checks passed on 2026-09-24. Idle lock, screens-off
  and Caffeine confirmed working by Suraj on 2026-09-25. The Gaming Mode round-trip remains
  pending; see PHASE0.md.

### 2.3 Known gaps (what this spec fixes)
| Area | Problem |
|---|---|
| Portals | Only `xdg-desktop-portal-hyprland`. There's no FileChooser backend, so "Open/Save" dialogs are missing for portal apps and Flatpaks. `modules/xdg_portal.lua` kills and restarts portals by hand. |
| Secrets | No keyring. Browser/editor/Discord secrets and saved Wi-Fi PSKs have nowhere safe to go. |
| Theming | `GTK_THEME=Adwaita:dark` env var (breaks libadwaita apps). No Qt theming. `nordic-theme` (AUR) is still the GTK settings/gsettings theme; only D-Bus-activated GTK apps without `GTK_THEME` (e.g. `xdg-desktop-portal-gtk` file dialogs) render with it. |
| Defaults | No `mimeapps.list`, no `xdg-user-dirs`. |
| Leftovers | Configs for waybar, wofi, mako, swaylock, wlogout, kitty and alacritty remain. `hypr/scripts/volume` points at mako icons. `hypr/scripts/swww-random-*` still call `swww`. |
| Sleep | Nothing locks the session before suspend or on `loginctl lock-session`. |
| Shell | Top bar only. Network, Bluetooth and brightness are polled via CLI. Bluetooth has no device list. No settings UI, polkit agent, device panel or update notifier. |
| Session | Hyprland runs apps directly (no systemd user session / XDG autostart). |
| Packages | `desktop-core.txt` contains the AUR/non-official `matugen-bin`, `nordic-theme`, `sddm-theme-tokyo-night-git`, `grimblast-git` and `quickshell-git`. |

---

## 3. Target architecture

```
                    ┌───────────────────────── frame (Top layer, click-through) ─────────────────────────┐
                    │  notification drawer grows from the top-right corner ─────────────────────────┐    │
                    │                                                                                │    │
                    │     windows (tiled inside the frame; exclusive zones = frame + pill rest)     OSD  │
                    │                                                                          (right edge)│
                    │                                                                                     │
                    │                      ╭──── pill: rest ↔ hover ↔ surfaces ────╮                      │
                    └──────────────────────┴───────────── bottom edge ─────────────┴──────────────────────┘
```

### 3.1 Windows (layer surfaces) per monitor
| Window | Layer | Purpose | Input |
|---|---|---|---|
| `ReserveBottom` | Top | Zero-content strip. `exclusiveZone = frameThickness + pillRestHeight` | none |
| `ReserveTop/Left/Right` | Top | `exclusiveZone = frameThickness` | none |
| `Frame` | Top | Draws the rounded-inner-corner frame | Empty `mask` (fully click-through) |
| `PillOverlay` | Overlay | Full-screen transparent surface hosting the **one** pill item + shoulders; also the notification drawer and OSD | `mask` = pill rect at rest; whole surface when a surface is open (backdrop click dismisses) |

Fullscreen: when the monitor's active workspace has a fullscreen window, the frame
**and** the pill overlay must set `visible: false`. Being transparent is not enough:
any mapped surface above a fullscreen window breaks direct scanout, VRR and tearing.
The one exception is the explicit peek (§3.3).

### 3.2 Pill states
All sizes are logical px at scale 1. Clamp widths to
`screen.width - 2*frame - 2*shoulder - 40`.

| State | Size (w×h) | Trigger | Content |
|---|---|---|---|
| `rest` (style `tab`, default) | 230×30 | default | workspace dots (active one elongated) + clock |
| `rest` (style `handle`) | 120×6 | default when `pill.restStyle = "handle"` | none (thin line). Reserve drops to `frame + 6` |
| `hover` | min(1200, clamp)×46 | pointer in the bottom 4 px strip for ≥150 ms (dwell), or double-tap Super | full bar row (§3.4) |
| `dashboard` | 920×420 | click the clock in the bar, `Super+D`, `qs ipc call pill open dashboard` (`open media`: Media tab) | Dashboard / Media / Performance / Weather tabs |
| `launcher` | 640×470 | `Super+Space` (unchanged), `Super+V` (clipboard mode) | search + results (Phase 5) |
| `sound` / `network` / `bluetooth` / `notifs` / `system` / `power` / `devices` / `settings` | per surface, ≤ 920×560 | click the matching bar item | re-hosted views (Phase 4/6) |
| `hidden` | — | fullscreen on this monitor, and not peeking | nothing mapped |

- The **bar row stays the base** of every surface. Surfaces grow **upward** from it.
- Leaving hover: collapse back to rest 300 ms after the pointer leaves, unless a
  surface is open or the pill is pinned.
- `Escape` closes a surface. Clicking the backdrop closes it. Opening a second surface
  morphs directly from the first (no close-then-open).

### 3.3 Fullscreen peek
Double-tapping Super toggles `peek` on the focused monitor. Peeking maps the pill in its
`hover` state over the fullscreen window. The frame stays hidden. It un-peeks on
`Escape`, on pointer leave (after 800 ms), or when the fullscreen state changes.

### 3.4 Bar row (hover state), left to right
workspaces 1–5 (pill chips; active = accent fill; occupied chips show 2-letter app
hints from toplevels) · active window title (elided) · **clock at the true centre** ·
spacer · CPU% · RAM% · tray (`SystemTray`) · network/Bluetooth/volume icons · Caffeine
and Game Mode chips (only when active) · update badge (Phase 6) · power.
(Changed in 4.4 with Suraj: no now-playing text; the dashboard's Media tab and the media
keys cover it, and the clock moved from the right end to the centre.)
Scrolling on workspaces switches workspace. Scrolling on the volume icon changes volume.

### 3.5 Notifications and OSD
- Toasts: a drawer grows from the frame's **top-right corner** (360 px wide, up to 4
  stacked). The notification *centre* is the `notifs` pill surface.
- OSD (volume/brightness/mic): a vertical 52×220 tab growing from the **right edge**,
  vertically centred, with shoulders. It disappears after 2 s.

### 3.6 Per-monitor behaviour
Config `monitors.<name>` can override any `pill.*` key. Default: both monitors identical.
Recommended for `HDMI-A-1` (the Discord screen): `{ "pill": { "hoverExpand": false } }`,
so the rest tab still shows but only expands on click. **ASK** Suraj which he wants
before shipping Phase 4.

---

## 4. Keybinds

### 4.1 Existing — must keep working, same keys
| Keys | Action |
|---|---|
| `Super+Return` | ghostty |
| `Super+C` | close window |
| `Super+E` | thunar |
| `Super+B` | firefox |
| `Super+P` | toggle float |
| `Super+Shift+P` | pseudotile |
| `Super+F` | fullscreen |
| `Super+Shift+F` | float the whole workspace (Lua state in `binds.lua`) |
| `Super+Space` | launcher → now opens the pill `launcher` surface |
| `Super+W` | workspace overview (existing overlay, keep) |
| `Super+V` | clipboard → now opens launcher in clipboard mode (replaces wofi) |
| `Super+Shift+W` | wallpaper picker |
| `Super+Shift+S` | **Gaming Mode** (FROZEN) |
| `Super+6..0` / `Super+Shift+6..0` | go to / move window to workspace 1–5 |
| `Super+arrows` / `Super+Shift+arrows` | focus / move |
| `Super+Shift+N`, `Alt+Shift+S` | magic scratchpad |
| `Alt+M`, `Alt+Return` | spotify / term scratchpads |
| `Super+scroll`, `Super+LMB/RMB` | workspace scroll, drag/resize |
| `Print`, `Ctrl+Shift+S` | screenshot screen / area (shell overlay) |
| `Ctrl+Alt+L` | lock (hyprlock) |
| `XF86Audio*` | volume/media |

### 4.2 New binds (and only these)
| Keys | Action | Lua |
|---|---|---|
| Double-tap Super (release, alone) | peek / expand pill | `hl.bind("SUPER + SUPER_L", <Lua function counting taps in a 300 ms hl.timer window>, { release = true })`; only a double tap runs `qs ipc call pill peek` |
| `Super+D` | dashboard surface (toggle) | `hl.dsp.exec_cmd("qs ipc call pill toggle dashboard")` |
| `Super+slash` | keybind cheatsheet | `hl.dsp.exec_cmd("qs ipc call cheatsheet toggle")` |

Add `{ description = "…" }` to **every** bind in `binds.lua` (the key and action stay
the same). The cheatsheet reads these descriptions from `hyprctl binds -j`.
The existing repo uses `qs msg <target> <fn>` (in `binds.lua` and
`extract-accent.sh`). In Quickshell 0.3.1, `msg` is marked **deprecated**
("Moved to `ipc call`"). Replace every occurrence with `qs ipc call <target> <fn>` in
Phase 0 (`rg -n 'qs msg' .config scripts`).

---

## 5. Design system

Keep `theme/Theme.qml` as the single source of tokens. Add the new ones there;
never hard-code them in components.

### 5.1 Existing identity (do not change)
- Font: **JetBrains Mono Nerd Font** (`ttf-jetbrains-mono-nerd`).
- Text `#cdd6f4`, dim ramps at 0.7 / 0.5 / 0.35 / 0.2 alpha.
- Surfaces: popup `rgba(15,12,20,0.80)`, bar `rgba(15,12,20,0.55)`, tiles `rgba(255,255,255,0.05)`.
- Accent: dynamic per monitor from the wallpaper (`extract-accent.sh` →
  `~/.cache/quickshell/accent[-MON]` → `accent update` IPC). Fallback `#00ffea`.
- Secondary colours: purple `#c678dd`, pink `#ff6ec7`, teal `#0adb9d`, turquoise `#40e0d0`,
  green `#39ff14`, orange `#ff9f43`, red `#f38ba8`.
- Active states: accent at 0.1 fill / 0.3 border. Radius: tiles 12, cards 14–20.

### 5.2 New tokens
| Token | Value |
|---|---|
| `frameBg` | `#110d17` (opaque — the frame, pill, shoulders, drawers and OSD are one material) |
| `frameThickness` | 10 |
| `frameRadius` | 22 (inner corner radius) |
| `shoulderRadius` | 22 (concave joins where a drawer meets the frame) |
| `pillRestTab` | 230×30 · `pillRestHandle` 120×6 · `pillHoverH` 46 · `pillHoverMaxW` 1200 |
| `pillRadiusSmall` / `pillRadiusSurface` | 16 / 26 (top corners only; the bottom sits on the frame) |
| `morphDuration` | 420 ms · `glideDuration` 240 ms (rest↔hover only) |
| `morphCurve` | cubic-bezier(0.16, 1, 0.3, 1) → `Easing.BezierSpline`, `bezierCurve: [0.16,1,0.3,1,1,1]` |
| `hoverDwell` | 150 ms · `collapseDelay` 300 ms · `peekLeaveDelay` 800 ms |
| `notifDrawerW` | 360 · `osdTab` 52×220 |

### 5.3 Shape
Draw the pill **and** its two shoulders as a single `QtQuick.Shapes` `ShapePath`. Do not
use stacked rectangles: the concave shoulders must join seamlessly with the frame edge.
Animate `width`/`height` of the pill item; the path binds to them. Content inside
cross-fades (opacity 0→1 over the last 40% of the morph). The same shape technique is
used for the notification drawer (top-right) and the OSD (right edge).

### 5.4 Motion and Game Mode
When `DesktopServices.gameMode` is on, set every duration to 0 (no morphs).
Honour a global `appearance.animations` config switch too.

---

## 6. Phases

> Each task lists **Files**, then **Do**, then **Check**. "Check" items are the acceptance
> criteria. Record anything you couldn't verify in the PR/commit message.

### Phase 0 — Baseline on `feat/de-shell`
**0.1 Apply and smoke-test the existing branch work**
- Do: prepare the two patches on `feat/de-shell`, correct the baseline bugs, and
  migrate `qs msg` callers without changing key semantics. Run
  `python3 scripts/check-desktop-phase0.py` (repository-only).
- Then **ASK** before backing up/deploying the separate live config copies and
  restarting the selected shell instance. Do not start a second desktop shell.
- Check:
  - no QML errors in the `qs` log
  - bar workspace pills switch workspaces
  - overview click and 1–5 keys work
  - Session → Logout exits Hyprland
  - System tab → Mixer opens pavucontrol floating
  - `qs ipc call desktop status` prints state
  - Caffeine tile shows the bar coffee chip, and `IdleInhibitor` blocks idle (check
    with `hyprctl` / wait past the lock timeout)
  - launching a game with `gamemoderun` shows the controller chip within 5 s, enables
    DND, disables blur (`hyprctl -j getoption decoration:blur:enabled` →
    `"bool": false`), and restores both on exit.
  - Manual on/off without a game does not suppress the next game's auto mode.
  - Rapid toggles reach the final requested state; failures appear in desktop status.
  - DND, animations, blur and inactive opacity restore to their pre-game values,
    including after an approved shell restart. Run the Gaming Mode round-trip.

**0.2 Switch to official Quickshell**
- Observed: Quickshell is already release 0.3.1 (`0.3.1-1.1`, CachyOS build), not
  `quickshell-git`. No replacement is needed merely to obtain these APIs.
- **ASK** before a package change. If the official Arch build is chosen, explicitly
  select `extra/quickshell` in a dependency-compatible transaction; unqualified
  package names can select CachyOS first. Do not alter Gaming Mode packages/repos.
- Check: repeat 0.1. Compare `pacman -Si extra/quickshell` with the installed version
  and packager; `pacman -Qi` does not record a source repository. Record the actual
  package transaction as provenance, not just the package name.

### Phase 1 — Official-only package manifest
**1.1 Clean `packages/desktop-core.txt`**
- Replace or remove:

  | Now | Change to | Why |
  |---|---|---|
  | `quickshell-git` | `quickshell` | in `[extra]` (0.3.1) |
  | `matugen-bin` | `matugen` | in `[extra]` (4.2.0) |
  | `grimblast-git` | remove | the shell's `ScreenshotOverlay` captures with `grim` and draws the area selection in QML (`slurp` stays for scripts) |
  | `nordic-theme` | `adw-gtk-theme` | in `[extra]`; recoloured by matugen (Task 2.3) |
  | `sddm-theme-tokyo-night-git` | remove | login uses qylock themes (installed from git by script, not a package) |
  | `paru` | leave helper bootstrapping in bootstrap; remove the active desktop-core entry | an active non-official entry would fail the manifest check |
  | `wlsunset` | `hyprsunset` | wlsunset last updated in `[extra]` 2024-04; hyprsunset is Hyprland-native (Task 2.6) |

- Add (all verified in official repos on 2026-09-23):

  | Package | Repo | For |
  |---|---|---|
  | `xdg-desktop-portal-gtk` | extra | FileChooser/Settings portal backend |
  | `gnome-keyring`, `libsecret` (core), `seahorse` | extra/core | secrets + GUI |
  | `qt6ct`, `qt5ct`, `kvantum`, `kvantum-qt5` | extra | Qt theming |
  | `adw-gtk-theme` | extra | GTK3 theme that follows libadwaita colours |
  | `xdg-user-dirs` | extra | standard folders |
  | `wl-clip-persist` | extra | clipboard survives app exit |
  | `hyprsunset` | extra | night light |
  | `libqalculate` | extra | `qalc` for launcher calculator |
  | `pacman-contrib` | extra | `checkupdates`, `paccache` |
  | `udisks2`, `udiskie`, `gvfs`, `gvfs-mtp`, `gvfs-smb` | extra | devices, phones, SMB shares |
  | `bluez`, `bluez-utils` | extra | BlueZ daemon (required by `Quickshell.Bluetooth`) |
  | `ddcutil` | extra | external monitor brightness |
  | `system-config-printer` | extra | printer setup GUI (CUPS already installed) |
  | `uwsm` | extra | **Phase 7 only.** Don't add to desktop-core until then |
  | `kdeconnect` | extra | optional, put in `daily-apps.txt` behind a comment; **ASK** |

- Also create `scripts/check-official.sh`. It reads a manifest, runs `pacman -Si` for
  every entry, and fails (listing the offenders) if any entry's repo is not
  `core|extra|multilib`. Wire it into `bootstrap-arch.sh --dry-run` for
  `desktop-core.txt` only.
- Run `scripts/sync-readme-pkglist.sh` to regenerate the README list.
- Check: `scripts/check-official.sh packages/desktop-core.txt` exits 0.
  `bootstrap-arch.sh --dry-run` passes.

### Phase 2 — Desktop plumbing (no visual change)
**2.1 Portals**
- Files: new `.config/xdg-desktop-portal/hyprland-portals.conf`:
  ```ini
  [preferred]
  default=hyprland;gtk
  org.freedesktop.impl.portal.FileChooser=gtk
  org.freedesktop.impl.portal.Settings=gtk
  org.freedesktop.impl.portal.Secret=gnome-keyring
  ```
  Delete `modules/xdg_portal.lua` and its `require`. Portals are D-Bus/systemd-activated
  and don't need manual restarts. **Keep** the portal recovery inside
  `gaming-desktop-restore` (frozen).
- Check: Firefox "Save Page As" and a Flatpak app's file dialog open a GTK picker.
  `busctl --user tree org.freedesktop.portal.Desktop` lists FileChooser. A Discord
  screen-share still works (hyprland portal). The Gaming Mode round-trip still restores
  portals.

**2.2 Keyring**
- Do: **ASK** before touching `/etc/pam.d/sddm`. Arch's default SDDM PAM already
  contains `-auth optional pam_gnome_keyring.so` and
  `-session optional pam_gnome_keyring.so auto_start`. Verify these lines, don't
  duplicate them. Enable `gnome-keyring-daemon.socket` for the user if the Arch wiki
  (GNOME/Keyring) says to for non-GNOME sessions. Export `SSH_AUTH_SOCK` only if Suraj
  wants the keyring's SSH agent (**ASK**).
- Note: the Gaming Mode return uses a transient SDDM autologin, which can't unlock the
  keyring. Apps will prompt once after returning. Document this in `docs/gaming-mode.md`
  **only with approval** (frozen file). Otherwise note it in this spec's Change log.
- Check: `secret-tool store --label=t test k v && secret-tool lookup test k` works after
  a fresh login, without prompting.

**2.3 Theming from one source**
- Remove `hl.env("GTK_THEME", "Adwaita:dark")` from `modules/env.lua`.
- Add `hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")` (qt5ct reads the same variable for Qt5).
- Set GTK through gsettings at login (idempotent script,
  `.config/quickshell/scripts/apply-theme.sh`, called from autostart):
  `gtk-theme 'adw-gtk3-dark'`, `color-scheme 'prefer-dark'`, `icon-theme 'Papirus-Dark'`,
  `font-name`/`monospace-font-name` JetBrains Mono, `cursor-theme`/`cursor-size` matching
  `XCURSOR_*`.
- matugen templates (`.config/matugen/config.toml` + `templates/`). Generate from the
  current wallpaper:
  - `~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` (libadwaita named colours:
    `@define-color accent_color …` etc.)
  - `~/.config/qt6ct/colors/matugen.conf` + `qt6ct.conf` pointing at it (same for qt5ct)
  - `~/.config/ghostty/themes/matugen` + an include from the ghostty config
  - `~/.config/hypr/hyprlock.conf`: move the heredoc out of `extract-accent.sh` into a
    matugen template
  - Hyprland border colours via `hyprctl eval 'hl.config({ general = { col = { active_border = "rgba(…)" } } })'`.
    Check the exact key names in the stubs first.
- `extract-accent.sh` keeps its job: picking the neon-boosted accent for the shell.
  Call `matugen image <wall>` from the same place so everything updates together.
- Remove `nordic-theme` and `adwaita-dark` from the machine only after Suraj confirms
  (they're in his AUR list).
- Check:
  - Changing wallpaper recolours the shell, GTK apps (thunar, file-roller), Qt apps
    (qt6ct preview, the polkit dialog), Ghostty (new window) and hyprlock.
  - A libadwaita app (e.g. Seahorse) renders without the "GTK_THEME set" breakage.

**2.4 Defaults and folders**
- Files: `.config/mimeapps.list` (browser `firefox.desktop`, files `thunar.desktop`,
  text/code `codium.desktop`, images/video/audio → ask Suraj, archives
  `org.gnome.FileRoller.desktop`, `x-scheme-handler/terminal` → ghostty).
  `.config/user-dirs.dirs` is generated by `xdg-user-dirs-update`, so call it in
  bootstrap rather than committing the file.
- Check: `xdg-mime query default inode/directory` → thunar. `xdg-open https://…` → firefox.

**2.5 Remove leftovers**
- Keep Wofi and its config until Phase 5 replaces and tests `Super+V`.
- Delete `.config/{waybar,mako,swaylock,wlogout,kitty,alacritty}` **after**
  confirming nothing references them (`rg -n 'waybar|wofi|mako|swaylock|wlogout|kitty|alacritty' .config scripts packages`).
- Fix `hypr/scripts/volume` (it points at mako icons; probably unused now that the shell
  OSD exists, so delete it if unreferenced).
- Delete `hypr/scripts/swww-random-*` (the `swww` binary is gone; `awww` replaced it)
  if unreferenced.
- Remove `wl-clipboard-history -t` from `autostart.lua` (dead package). Add
  `wl-clip-persist --clipboard regular`.
- Check: `rg` finds no references. No errors in `hyprctl configerrors`.

**2.6 Night light → hyprsunset**
- Do: replace `wlsunset` in `autostart.lua` and in `DesktopServices.qml`.
  - Run `hyprsunset` as a daemon with a schedule config
    (`~/.config/hypr/hyprsunset.conf`, profiles for 19:30 warm / 09:00 identity —
    check the syntax on the hyprsunset wiki page. hyprsunset has its **own** config
    parser (hyprlang when this was written); it does not read Hyprland's Lua config).
  - The toggle uses `hyprctl hyprsunset identity` / `hyprctl hyprsunset temperature 4500`.
    **Verify these IPC commands still work under the Lua Hyprland config**, because
    hyprctl forwards them to the hyprsunset socket.
  - `nightLight` state = "current temperature ≠ identity".
- Check: toggle on/off from the tile, the launcher `> Night Light`, and IPC. The schedule
  applies after a restart.

**2.7 Lock before sleep and on `loginctl lock-session`**
- Do: nothing listens to logind's `Lock` / `PrepareForSleep` signals today. Add a
  user service `.config/systemd/user/session-lock-listener.service` running a tiny
  script. It uses `busctl --user`/`dbus-monitor --system` on
  `org.freedesktop.login1.Session.Lock` and `org.freedesktop.login1.Manager.PrepareForSleep`
  and runs `pidof hyprlock || hyprlock`, using a delay inhibitor
  (`systemd-inhibit --what=sleep --mode=delay`) so the lock paints before suspend.
  **Alternatively**, if `hypridle` (extra) is acceptable *only* for `lock_cmd` /
  `before_sleep_cmd` with no listeners, that is simpler. **ASK** which Suraj prefers.
  Don't run two idle managers with listeners.
- Check: `loginctl lock-session` locks. `systemctl suspend` → hyprlock is visible on resume.

### Phase 3 — Shell restructure (no visual change yet)
**Status (reviewed 2026-09-26):** service extraction is implemented, but Phase 3 has
not passed all acceptance gates. Brightness review fixes are deployed with Suraj's
approval. Wi-Fi/Bluetooth/brightness visual checks and the supervised Gaming Mode
round-trip are still required before starting Phase 4.

Move logic out of `shell.qml` into **singletons** under `.config/quickshell/services/`
(`pragma Singleton`, registered via a `qmldir`), so both the old bar and the new pill can
use them during the migration.

| Singleton | Replaces | Backed by |
|---|---|---|
| `Config` | hard-coded values (London weather, timeouts, ddcutil buses 8/10, night-light times) | `FileView` + `JsonAdapter` on `~/.config/quickshell/settings.json`, `watchChanges: true`; defaults in QML; per-monitor overrides under `monitors` |
| `Notifs` | notification state in `ShellRoot` | `NotificationServer` (keep `keepOnReload`) |
| `Audio` | `pactl`/`wpctl` polling in SoundView/Volume/OSD | `Quickshell.Services.Pipewire` |
| `Net` | `nmcli` polling in SystemView | `Quickshell.Networking` (NetworkManager backend) |
| `Bt` | `bluetoothctl` polling | `Quickshell.Bluetooth` (adapters, devices, pair/connect/trust) |
| `Brightness` | ddcutil calls in SystemView | `ddcutil` (keep; there's no native module). Bus numbers come from `Config`. Add a one-time `ddcutil detect --brief` at startup to map buses to monitors |
| `Media` | MPRIS logic in `ShellRoot` | `Quickshell.Services.Mpris` |
| `Sysmon` | SysInfo polling | `/proc` via `FileView` (cpu, mem) + `sensors`/amdgpu sysfs for GPU temperature |
| `Weather` | BarClock curl | keep wttr.in, location from `Config` |
| `Desktop` | `components/DesktopServices.qml` | move as-is, then switch night light to hyprsunset (2.6) |
| `Hypr` | scattered `Hyprland.*` usage | helper `dispatch(lua)`, `focusedMonitor`, `isFullscreen(monitorName)` |

- Settings JSON schema (initial):
  ```json
  {
    "pill": { "restStyle": "tab", "hoverExpand": true, "hoverDwellMs": 150 },
    "idle": { "lockSec": 600, "dpmsSec": 900, "suspendSec": 0 },
    "nightLight": { "warmK": 4500, "on": "19:30", "off": "09:00" },
    "weather": { "location": "London" },
    "brightness": { "buses": { "DP-2": 10, "HDMI-A-1": 8 } },
    "appearance": { "animations": true },
    "monitors": { "HDMI-A-1": { "pill": { "hoverExpand": false } } }
  }
  ```
  Implemented settings: `idle`, `weather`, and optional `brightness.buses` overrides.
  Omit `brightness.buses` (or use `{}`) for startup detection; explicit connector-to-bus
  entries override detected entries and reset to detection when removed. Only nonnegative
  integer bus numbers are accepted. DP-2 = 10 and HDMI-A-1 = 8 were observed on this host;
  these are examples, not portable defaults. The classic slider still sets all detected/
  configured buses; per-monitor controls remain deferred. Other settings in this target
  schema arrive with their consumers: pill/appearance/monitor layout in Phase 4, night-light
  schedule editing in Phase 6 (the current schedule stays in hyprsunset.conf).
- Check: the old top bar still works, with identical behaviour, on top of the singletons.
  `nmcli`/`bluetoothctl` polling loops are gone (`rg 'nmcli|bluetoothctl' .config/quickshell`
  shows only fallbacks, if any). Editing `settings.json` live-updates the shell.

### Phase 4 — Frame + pill (the visual change)
Build this behind a switch: `Config.appearance.layout = "frame" | "classic"`, default
`"classic"` until Phase 4 passes, then flip it. Keep `classic` working until Phase 8.
(Flipped 2026-09-26 at Suraj's request, with the live fullscreen and Gaming Mode checks
still to run; see the change log.)

**4.1 Frame + reserves** (`components/frame/Frame.qml`, `Reserve.qml`)
- Four reserve windows plus one click-through frame window per screen, as in §3.1. The
  frame uses `ShapePath` with `frameRadius` inner corners.
- Adjust `general.gaps_out` in `options.lua` so windows sit ~12 px inside the frame's inner
  edge (the exclusive zones already push them in; reduce `gaps_out` accordingly).
- Hide the frame on fullscreen (per monitor).

**4.2 Pill** (`components/pill/Pill.qml`, `PillShape.qml`, `PillBar.qml`)
- One `PillOverlay` window per screen, on the Overlay layer, with the mask rules from §3.1.
- State machine (§3.2) and the morph, glide and dwell timings from §5.2. Hover detection:
  a 4 px `MouseArea` hot zone along the bottom edge inside the overlay mask, plus
  `HoverHandler` on the pill.
- `PillBar.qml` renders the rest content and the full bar row (§3.4) from the singletons.
- Fullscreen hide and double-tap-Super peek (§3.3). IPC target `pill`: `peek()`,
  `open(name)`, `close()`, `toggle(name)`.

**4.3 Re-host existing surfaces** inside the pill: `sound` (SoundView), `notifs`
(NotifsView), `system` (SystemView). Their content stays the same, only the container
changes. `UnifiedPanel`'s tab strip becomes redundant in frame mode.

**4.4 Dashboard surface** (`components/pill/surfaces/Dashboard.qml`)
- Tabs: Dashboard (user card with `~/.face` avatar, uptime + kernel, weather, month
  calendar, media card with art and controls) · Media (large art; cava-style bars are
  **optional** — verify `cava` with `pacman -Si cava` first, and skip unless cheap) · Performance (CPU/GPU/RAM/
  storage rings) · Weather (7-day).

**4.5 Notification drawer and OSD** re-implemented as edge drawers (§3.5).
`NotificationToasts` and `OSD` logic moves in; the old windows are kept for `classic`.

- Check:
  - Every state in §3.2 reachable by mouse **and** keyboard/IPC.
  - Windows never move when the pill expands.
  - With a fullscreen game (or `mpv --fs`): `hyprctl layers` shows no Quickshell
    surface mapped on that monitor, and VRR/tearing still engage
    (`hyprctl monitors` / MangoHud).
  - HDMI-A-1 follows its per-monitor config.
  - Desktop Game Mode disables the morphs.
  - The Gaming Mode round-trip passes.
  - Screenshots of each state are attached to the commit/PR description.

### Phase 5 — Launcher, clipboard, cheatsheet
**5.1 Launcher modes** (in the pill `launcher` surface; logic ported from `AppLauncher.qml`)
- `apps` (default, existing category/grid logic) · `=` calculator
  (`qalc -t -e -- <expr>`, 140 ms debounce, Enter copies the result via `wl-copy`) ·
  `>` actions: gaming, gamemode, caffeine, nightlight, dnd, wallpaper, overview,
  cheatsheet, screenshot, lock, suspend, logout, reboot, poweroff → `runShellAction(id)`.
  Destructive ones (reboot/poweroff/logout) need a second Enter within 3 s.
- Clipboard mode (`Super+V`): `cliphist list`. Enter runs
  `printf '%s' "$line" | cliphist decode | wl-copy`. Del or middle-click deletes
  (`cliphist delete`). Image entries show a thumbnail (decode to a temp PNG, lazily).
- Remove the wofi command from `binds.lua` (Super+V stays, and now calls
  `qs ipc call launcher clipboard`).
- Check: each mode works by keyboard only. Super+V toggles. `wofi` is no longer referenced.

**5.2 Keybind cheatsheet** (`Super+slash`)
- Parse `hyprctl binds -j`. Decode `modmask` bits (SHIFT 1, CAPS 2, CTRL 4, ALT 8, MOD2 16,
  MOD3 32, SUPER 64, MOD5 128). Group by the `description` prefix
  (`"Apps: Terminal"` → group Apps). Filter field. Escape closes.
- Check: every bind in `binds.lua` appears with a description.

### Phase 6 — KDE-level features
**6.1 Polkit agent** (`components/PolkitDialog.qml`, `Quickshell.Services.Polkit`)
- Themed password dialog as a centred overlay (not a pill surface; it must work even
  when the pill is hidden). Supports identity choice, error state and cancel.
- Remove `polkit-kde-agent` from autostart **only after** it works (keep the package as a
  fallback until Phase 8).
- Check: `pkexec true`, `systemctl restart` of some unit, and GParted/virt-manager
  prompts all show the dialog. Only one agent is registered.

**6.2 Bluetooth and Wi-Fi surfaces**
- `network` surface: list, connect, forget, and hidden SSID via
  `Quickshell.Networking`. Password entry is inline — no more spawning ghostty +
  `nmcli --ask`.
- `bluetooth` surface: power, scan, pair/trust/connect, battery % when exposed.
- Check: connect to a protected network inline. Pair a device from scratch.

**6.3 Devices surface** (removable media)
- There is no Quickshell UDisks module. Keep `udiskie` as the automount daemon
  (`udiskie --no-tray --notify`, autostart), and build the `devices` surface on
  `udisksctl` + `lsblk -J -o NAME,LABEL,SIZE,MOUNTPOINTS,HOTPLUG,RM`, refreshed on
  `udisksctl monitor` output. Actions: open in thunar, unmount, power-off.
- Check: plug in a USB stick → a toast appears, then open/eject from the surface.

**6.4 Update notifier**
- A `Updates` singleton runs every 60 min and on demand: `checkupdates` (pacman-contrib;
  it uses its own db copy, so it's safe) + `flatpak remote-ls --updates` +
  `paru -Qua` **only if `paru` exists** (optional; AUR updates are informational).
- The bar badge shows the count. Clicking it opens a small surface with counts per source
  and an "Update" button that spawns `ghostty -e paru` (or `sudo pacman -Syu` if paru is
  missing) in a floating window.
- Check: the badge appears when updates exist. Nothing ever runs `-Syu` automatically.

**6.5 Settings surface ("System Settings")**
- A pill surface (up to 920×560) with a left-hand section list, writing
  `settings.json` through `Config`:
  - **Appearance:** wallpaper picker (reuse), rest style tab/handle, animations toggle,
    accent preview.
  - **Displays:** read-only list from `hyprctl monitors -j` + "Open nwg-displays". Don't
    write `monitors.lua` from the shell in this phase.
  - **Sound:** default sink/source (Pipewire).
  - **Network / Bluetooth:** links to their surfaces.
  - **Power & idle:** the three timeouts + suspend toggle.
  - **Night light:** temperature + schedule.
  - **Default apps:** read/write `mimeapps.list` for browser/files/terminal/text/images.
  - **Gaming:** read-only status of Gaming Mode prerequisites (`/usr/local/bin/switch-to-gaming`
    exists, `gamemoded` present) + the Desktop Game Mode auto toggle.
  - **Keybinds:** opens the cheatsheet.
  - **About:** versions of Hyprland/Quickshell/kernel.
- Check: every control round-trips through `settings.json` and survives a shell restart.

### Phase 7 — uwsm session (GATED: touches Gaming Mode)
**Do not start without Suraj's written approval.**
- Why: a systemd user session gives proper XDG autostart (`~/.config/autostart`),
  ordered services and a clean logout.
- Risk: `deploy/gaming/usr/local/bin/gaming-session-switch` hard-codes
  `DESKTOP_SESSION="hyprland"` and rewrites SDDM's `state.conf` to
  `/usr/share/wayland-sessions/hyprland.desktop`. Under uwsm the session is
  `hyprland-uwsm` (verify that `/usr/share/wayland-sessions/hyprland-uwsm.desktop` exists
  on the machine).
- Do:
  1. `sudo pacman -S uwsm`.
  2. Change `DESKTOP_SESSION` to `hyprland-uwsm` in the deploy copy **and** the
     installed `/usr/local/bin` copy.
  3. Launch apps via `uwsm app --` in `autostart.lua` and binds (terminal, file manager,
     browser, launcher `execute()` wrapper).
  4. Move env vars that must reach systemd into `~/.config/uwsm/env` / `env-hyprland`.
  5. Replace `hl.exec_cmd` autostarts that are really daemons (clipboard watchers,
     hyprsunset, udiskie, awww-daemon) with user services or `~/.config/autostart`
     entries.
  6. Remove the `dbus-update-activation-environment` / `import-environment` lines
     (uwsm does this).
- Check: log in via SDDM "Hyprland (uwsm-managed)". `systemctl --user list-units 'app-*'`
  shows apps as scopes. **Full Gaming Mode round-trip ×3** (enter, play, Steam → Exit to
  Desktop, `Super+Shift+R` exit, reboot straight after a switch). Keep the old
  `hyprland` session selectable as a fallback.

### Phase 8 — Cleanup and docs
- Remove the `classic` layout, `UnifiedPanel`, the old OSD/toast windows, the unused
  `SessionMenu.qml`, `ScreenshotOverlay` duplicates, and the `polkit-kde-agent` package
  (**ASK**).
- Update `README.md`: architecture summary, keybind table (§4), official-only package
  policy, how to theme, `settings.json` reference.
- Update `docs/bootstrap.md` for the new packages and user services.
- Check: fresh-install dry run passes. `check-official.sh` passes. There are no dead files
  (`rg` for removed component names).

---

## 7. Verification toolkit

### 7.1 After every task
```bash
hyprctl reload && hyprctl configerrors          # must be empty
pkill qs; qs -d                                   # or: qs --no-duplicate; watch the log
qs log | grep -iE 'error|warn' | grep -v '^$'     # no new errors
scripts/check-official.sh packages/desktop-core.txt
```

### 7.2 Visual
Take screenshots with `grim` of each pill state and surface on both monitors. Compare
them against §3/§5 and the mockup. Attach them to commits/PRs.

### 7.3 Gaming Mode round-trip (after every phase)
1. `Super+Shift+S` → Steam preflight → gamescope session on DP-2, and HDMI-A-1 goes dark.
2. Launch a game. Check HDR/VRR as before.
3. Steam → Power → Exit to Desktop → back in Hyprland. The shell relaunches, portals work
   (file dialog in Firefox), and HDMI-A-1 re-lights.
4. Repeat with `Super+Shift+R` inside Gaming Mode.
Any regression means **stop, revert the phase, and report**.

### 7.4 Desktop gaming
Run a game on the desktop with `gamemoderun %command%`. Check that Desktop Game Mode
turns on, DND is on, blur is off, the pill and frame hide on fullscreen, Discord on
HDMI-A-1 stays readable (no inactive dimming), and everything is restored on exit.

---

## 8. Open decisions (defaults in bold; ASK before Phase 4 ships)
1. Pill rest style: **tab** / handle. DECIDED 2026-09-26: tab.
2. Expand trigger: bottom-edge hover with 150 ms dwell + `Super+grave` / Super tap
   (release bind) / click only. DECIDED 2026-09-26: **hover dwell + double-tap Super**.
   `Super+grave` rejected: on Suraj's Moonlander grave is a tap-dance key (hold = Ctrl,
   ~200 ms tap delay). Live test of `SUPER + SUPER_L` with `release = true`: fires only
   when Super is pressed and released alone (not after Super+1, Super+Space or
   Super+drag); observed double-tap intervals 151 and 165 ms, so 300 ms is the window.
   Hyprland has no double-tap bind, so binds.lua counts taps (Lua function + oneshot
   hl.timer) and only a double tap spawns `qs ipc call pill peek`.
3. HDMI-A-1 pill: same as main / **rest-only, click to expand**. DECIDED 2026-09-26: default.
4. Lock-before-sleep: small logind listener service / **hypridle for sleep hooks only**.
   DECIDED in Task 2.7 (hypridle hooks, commit 00a8b8b).
5. KDE Connect: install or skip.
6. Keyring SSH agent: yes / **no**.

## 9. Out of scope
- Replacing SDDM with a Quickshell greeter (Gaming Mode relies on SDDM autologin).
- Bootable filesystem snapshots (systemd-boot can't boot snapshots without extra
  tooling; the filesystem is chosen interactively at install). Targeted config
  backups and reversible deployment are still required.
- AUR apps in `daily-apps.txt` / `gaming-mode.txt`, and the CachyOS gaming stack.
- Writing monitor layout from the shell (use nwg-displays).

## Change log
- 2026-10-03 - Phase 7 (uwsm), approved in writing by Suraj; uwsm 0.27.0 installed by Suraj.
  - Stage 1 `c104636`: `uwsm app --` for autostart, the app binds and the launcher; logout runs
    `uwsm stop` under uwsm; dropped the redundant dbus-update-activation-environment line
    (Hyprland 0.56 imports these itself). uwsm runs XDG autostart, which started
    xwaylandvideobridge (an uncloseable window) and nm-applet: both disabled with Hidden=true
    overrides in `.config/autostart/`. Backup `phase7-stage1-20261003-193533`.
  - Stage 2 `59438a3`: Gaming Mode returns to `hyprland-uwsm`; the installed 2026-07-14
    gaming-session-switch fix (recreate state.conf) synced into the repo. Steam's "Switch to
    Desktop" calls `steamos-session-select plasma` (gamescope-session-cachyos), never our
    os-session-select: it pointed SDDM at plasma.desktop (not installed) and stopped the session
    from under Steam, crashing gamescope; only the wrapper's fallback recovered (~25 s), and the
    July login screens were that fallback not running. New `/usr/local/bin/steamos-session-select`
    runs our switch instead. Backup `phase7-stage2-20261003-210143`.
  - `da723f7`: switch-to-desktop ran inside the gaming login session it ends, so from
    Super+Shift+R it died before the root helper set autologin (login screen). It now runs as
    the transient unit switch-to-desktop.service.
  - Live: three round trips passed (Switch to Desktop 8 s, Super+Shift+R 17 s, reboot from
    Gaming Mode to the login screen with hyprland-uwsm preselected). Lian Li back within 1 s.
    dunst masked (`systemctl --user mask dunst.service`): D-Bus started it at login, racing
    the shell for org.freedesktop.Notifications.
  - Kept: the plain `hyprland` session as a fallback, with its Lian Li start and portal-reset
    autostart lines (no-ops under uwsm).
  - Open: gamescope crashes on stop (harmless, after the switch); Hyprland segfaults on every
    exit, uwsm or not; SDDM's greeter exists ~1 s during a switch; first login after boot
    waits ~24 s for graphical.target (br0 stuck in DHCP holds NetworkManager-wait-online,
    which smb/nmb need). uwsm added to desktop-core.txt; dunst is not in the manifest, so a
    fresh install needs no mask.
- 2026-10-03 - Phase 8 code cleanup, approved item by item by Suraj; deployed live.
  Backup `phase8-classic-20261003-191917` (`files/` = the live files before the change).
  - `d51ecdc`: deleted `SessionMenu.qml` (nothing instantiated it).
  - `241ec5c`: removed the classic layout. Gone from shell.qml: the bar, launcher overlay,
    OSD and toast windows. Deleted: AppLauncher, BarClock, OSD, SysInfo, UnifiedPanel.
    `appearance.layout` is no longer read (an old key is ignored). Frame lost
    `reserveTop`/`pillShown`. Kept: NotificationToasts (the drawer reuses it) and
    ScreenshotOverlay (one copy, in use; no duplicate existed).
  - `43f7a64`: `polkit-kde-agent` dropped from desktop-core.txt and the README list.
    Suraj uninstalled it at 19:20:45 (no other packages removed); the shell's agent
    stays registered.
  - Checks: Phase 0/3/4 (full private-Xvfb run), JS service tests, check-official.
    Live: shell restarted with no QML errors, frame/pill/reserves per monitor, no classic
    windows, launcher IPC opens the pill surface.
  - Remaining Phase 8: README and bootstrap docs, deferred until after Phase 7 (uwsm) so
    they are written once.
- 2026-10-03 - Phase 6 live checks with Suraj. Backup `phase6-livecheck-20261003-190147`.
  - Passed: Default apps change and restore (Images to Firefox and back; only the six image
    defaults changed; mimeapps.list byte-identical to the backup afterwards). Browser could not
    be switched: Firefox is the only installed browser.
  - Passed: lock and screen-off timeouts, night light temperature, Game Mode auto toggle and
    default sink survived a Quickshell restart; polkit agent re-registered, no QML errors.
    Restored afterwards; night light now saved as 3500 K (was the 4000 K default).
  - Deferred by Suraj: Bluetooth pairing from scratch (no device to hand) and clean re-login
    autostart check. Phase 6 is otherwise complete.
  - Lian Li daemon now started from autostart (`297cde7`): it is PartOf graphical-session.target,
    which Gaming Mode's exit stops and plain Hyprland never restarts. Verify on the next Gaming
    Mode return. Phase 7 (uwsm) would make this line unnecessary.
- 2026-09-30 - Gaming Mode Steam preparation: scoped freeze exception approved by Suraj;
  this is NOT approval for the Phase 7 uwsm migration. Suraj tested `--prepare-only`
  successfully and installed the first version. A subsequent full-switch test exposed
  a readiness-parser bug. The corrected helper was installed (identical to the repo) and
  a full round-trip passed on 2026-10-03 (switch 18:33, back to Hyprland 18:41).
  Original installed helper backed up under
  `~/.local/state/dotfiles-backups/gaming-preflight-20260930-132342/switch-to-gaming`;
  it matched HEAD before backup. Nothing committed yet.
  - Full-switch attempt at 14:02 stayed in Hyprland: Steam emitted Verification complete,
    then an asynchronous Set status message: Verifying installation. The parser incorrectly
    reset readiness and kept waiting; no SDDM switch or monitor-disable step ran. Corrected
    readiness to ignore UI status messages (still usable for progress), with failing-then-
    passing regression coverage and a check that UI-only completion cannot authorize a switch.
  - Successful Gaming Mode round-trip reported. The fresh desktop on return is expected:
    the existing helper restarts SDDM rather than preserving the old Hyprland session.
  - Black-screen delay traced to Steam changing from desktop stable to `steamdeck_stable`
    at 12:15:05, downloading 148361 KB and finishing installation at 12:23:18. Desktop Steam
    changed back at 13:12:39 but reported Nothing to do (the channels then shared a version).
    Channel changes are confirmed; a download on every switch is not. The old wrapper's
    gaming-ready message is a fixed 20-second suspend-unmask timer, not Steam UI readiness.
  - `switch-to-gaming` now cleanly stops existing Steam and prepares a fresh launch with
    the same four options as CachyOS's steam-launcher. Replaces one progress notification;
    captures this launch's console output in `~/.local/state/gaming-mode/steam-preflight.log`
    (or XDG_STATE_HOME). Steam's native bootstrap log remains available. Required updates
    are moved before the session switch, not disabled or guaranteed to disappear.
  - Requires fresh verification, no updater and a running web helper over three polls;
    startup/update/shutdown failures stay on the desktop. This is a readiness heuristic,
    not proof that every Steam window has rendered. Timeout leaves Steam available to
    finish on the desktop. Concurrent requests are rejected with flock. `--prepare-only`
    performs preparation and clean shutdown without touching monitors or SDDM.
  - Phase0 permits changes only to this helper's preparation portion; dependency checks,
    monitor/session-switch tail and all other Gaming Mode files remain frozen. New isolated
    test covers existing/cold Steam, update/restart, stale logs, missing helper, startup and
    shutdown failures, timeout, cancellation, concurrency and prepare-only. No live switch
    or channel changes were performed by the assistant.
- 2026-09-29 - Lock screen guard, deployed and live-tested with Suraj. Backup
  `lock-guard-20260929-172414` (`files/`, `new-files.txt`, `v1/` = the first guard version).
  - Found: after a long idle (lock at 10 min, screens off at 30 min) Hyprland showed "lockscreen
    app died" and Suraj had to power off. No core dump, and nothing in the journal; hyprlock's
    output went to the shell's log in /run, lost on reboot. Matches the known hyprlock death when
    a monitor powers off (hyprlock#375, #953); DP-2 is a QD-OLED that goes into deep standby.
    Keeping screens on while locked was rejected (OLED burn-in).
  - `quickshell/scripts/lock.sh` runs hyprlock and starts it again at once if it exits without
    an unlock (quick repeated failures back off 1-4 s, then it gives up, so a broken hyprlock
    can't loop). flock keeps one guard; output goes to the journal (`journalctl -t hyprlock`,
    `-t hyprlock-guard`). `misc.allow_session_lock_restore = true` lets the new hyprlock take the
    existing lock.
  - Every lock path uses it: the shell's idle lock, launcher Lock and the classic session menu
    start it detached (the idle lock used to be a shell-owned child, killed by any shell
    restart), and hypridle's `lock_cmd` (lock-session, before sleep). Ctrl+Alt+L still runs plain
    hyprlock (frozen keybind).
  - Tests: `scripts/tests/test_lock_guard.py` (fake hyprlock: crash restarts in under 1 s, unlock
    ends, broken hyprlock gives up after 5, one guard, locked elsewhere), run by phase0. Live:
    `pkill -9 hyprlock` while locked was replaced in 44 ms (Hyprland's placeholder shows for a
    frame; the session stays locked) and the password worked; a 30 s DPMS off/on while locked did
    not kill hyprlock, so the long-standby trigger is still unconfirmed.
- 2026-09-29 - Phase 6.5b (Settings: displays, sound, network/bluetooth links, default apps,
  gaming), deployed live with a backup and verified (config loaded, polkit agent registered,
  hyprsunset still running). Backup `phase6-settings-b-20260929-133109` (`files/`, the live
  `settings.json` and `mimeapps.list`, `new-files.txt`).
  - Five new Settings sections, in order: Displays, Sound, Network & Bluetooth, Default apps,
    Gaming. Displays is read-only (parsed from `hyprctl monitors -j`, sorted by x, with a hint
    to edit hypr/modules/monitors.lua). Sound lists the PipeWire sinks and sources as selectable
    rows (the default device persists via WirePlumber, not settings.json) and links to the
    Volume surface. Network & Bluetooth are status rows whose buttons open their surfaces.
  - Default apps sets the browser, file manager, text editor and image viewer through
    `xdg-mime default` (the generic backend rewrites the live mimeapps.list in place, keeping
    comments, other keys and sections). The current default comes from `xdg-mime query default`;
    candidates come from every `applications/mimeinfo.cache` under XDG_DATA_HOME/XDG_DATA_DIRS,
    resolved through DesktopEntries.byId (hidden/unknown apps dropped); the current default is
    always offered first. Each category is an inline chooser (a button that expands to a
    candidate list; no popup window).
  - Gaming shows read-only status (the /usr/local/bin/switch-to-gaming helper, the gamemoded
    daemon, and whether a game is active now) plus a "Game Mode follows games" switch persisted
    as `gaming.autoGameMode` (default true = the old behaviour). Desktop's desiredGameMode
    binding now calls a pure wantGameMode(override, auto, active) function; a manual off still
    wins, and turning the auto toggle off only stops a game from auto-enabling it.
  - Deviations from the SPEC, both Suraj's call: no "Open nwg-displays" button (he doesn't use
    it, and it would save a hyprland.conf monitors.conf that this Lua config never loads), and
    no Default-apps terminal row (Ghostty is the only terminal, hardcoded in binds.lua and the
    shell, and xdg-terminal-exec is not installed; a MIME default for a terminal does not exist
    anyway).
  - Tests: unit tests for parseMonitors (both real monitors, sorted, 164.9 -> 165 Hz, invalid
    JSON), the xdg-mime defaults/candidates parsers, the gaming status parser and the
    wantGameMode truth table; phase4 with fake hyprctl/xdg-mime: both monitors listed, the sound
    empty state and link, the network/bluetooth links, the exact
    `xdg-mime default <id> <types...>` command and the row re-query, and the Game Mode auto
    toggle landing in settings.json (unknown keys kept). test_desktop_controller.js now also
    loads wantGameMode (the binding calls it) and stubs Config.gaming.autoGameMode. Rendered
    previews in `~/.cache/pill-preview/settings-b-{displays,sound,connections,defaults,gaming}.png`.
  - Not tested: a shell restart with `gaming.autoGameMode` false. It is read by the same
    Config path as `appearance.animations`, which phase4 checks at startup; the live check
    is Suraj's. Review fixes before commit: Displays cards right-align the mode/scale lines,
    the Sound link button says Open, and a second default-app pick is ignored while
    `xdg-mime` is still running.
- 2026-09-27 - Phase 6.5a (Settings surface: appearance, power & idle, night light, keybinds,
  about), deployed and committed with Suraj's approval (live: settings survive a restart,
  handle rest style opens on the rest-only monitor, Caffeine remembered). Backup `phase6-settings-20260927-214601`
  (`files/`, `files/hypr/`, the live `settings.json`, `new-files.txt`).
  - `settings` pill surface, 920x560 clamped: sections on the left, controls on the right.
    Opened from the System view's "All settings" row (frame mode), the launcher's
    `> Settings` action, or `qs ipc call pill open settings`.
  - `Config.set(path, value)`: re-parses settings.json, changes one key, writes the whole
    object back (2-space JSON; unknown keys kept; undefined deletes). It refuses while the
    file does not parse, so a half-saved hand edit is never overwritten.
  - Appearance: wallpaper picker (closes the surface, then opens it), rest style
    (`pill.restStyle`, global; per-monitor overrides still win), animations
    (`appearance.animations`), accent swatch. Power & idle: `idle.lockSec`, `dpmsSec`,
    `suspendSec` as choices (a hand-set value outside them is shown too; suspend Off is
    the toggle), Caffeine. Keybinds: opens the cheatsheet. About: OS, kernel, Hyprland,
    Quickshell.
  - Night light: hyprsunset 0.4 has no config-path option and its own profiles would
    fight any other schedule, so the schedule moved into the shell: `nightLight
    {temperature, from, to}` in settings.json (defaults 4000 K, 19:30 -> 09:00, the old
    profiles), applied through `hyprctl hyprsunset temperature N | identity` every minute,
    on settings changes and 0.7 s after hyprsunset starts. hyprsunset.conf keeps no
    profiles; autostart and the toggle start `hyprsunset --identity`. Deployed with a
    hyprsunset restart; the shell set 4000 K at 21:46 straight away.
  - Found while testing: a Flickable's content width follows its children (use the
    Flickable's width, also in the network/bluetooth lists), and a nested ColumnLayout
    fills by default and caps its width at its children's (the section list and the
    setting titles now say so explicitly). A phase4 harness artefact also surfaced:
    `xdotool key --window Escape` to the polkit prompt, which unmaps while handling it,
    left a phantom Escape that closed the next focused field; the test now sends real
    input (XTEST), which does not.
  - Tests: Config.set (one key, unknown keys kept, malformed refused, missing file,
    deletion), night light window (overnight, same-day, from == to) and exact hyprsunset
    commands, settings helpers; phase4 real clicks: System's link opens Settings, rest
    style, animations, lock/suspend, temperature and the from stepper each land in
    settings.json and take effect, unknown keys kept, a malformed file is never
    overwritten, Keybinds opens the cheatsheet.
  - From Suraj's live test: everything was remembered across a restart except Caffeine,
    which was session state (the deploy scripts had been re-enabling it). It is now
    `idle.caffeine` in settings.json: read at startup, written on every toggle (chip,
    System, Settings, launcher); if the file cannot be written it still toggles for the
    session.
  - From Suraj: with the handle rest style, the rest-only second monitor (HDMI-A-1,
    hoverExpand false) could not be opened: the click target was the rest shape itself,
    and the handle is 120x6 px floating above the frame band. The target is now the rest
    shape plus 24 px each side and 10 px above, down to the screen edge (so the pointer
    parked on the bottom edge under it works), in the input mask only at rest; a click
    there counts as a visit, so the pill collapses again after the pointer leaves. The
    rest of the bottom edge still passes clicks through. phase4 checks both clicks and
    the pass-through; phase3 checks idle.caffeine (true read, non-boolean rejected).
- 2026-09-27 - Phase 6.3 (devices surface), deployed and committed with Suraj's approval (live USB
  stick test: toast, chip, Open in thunar, Eject). Backup
  `phase6-devices-20260927-201408` (`new-files.txt`, `files/hypr/autostart.lua`).
  - `services/Devices.qml`: `lsblk -J` (NAME, PATH, LABEL, SIZE, FSTYPE, MOUNTPOINTS,
    HOTPLUG, RM, TYPE, VENDOR, MODEL, TRAN), refreshed 300 ms after `udisksctl monitor`
    output (restarted after 5 s if it exits). Only disks with hotplug or rm, and never a
    disk with anything mounted outside /run/media, so a system disk cannot show up with an
    Eject button (every internal disk here reports hotplug=0, rm=0). Volumes are the
    formatted, non-swap partitions (or the whole disk when unpartitioned).
  - Actions through udisksctl: Open (mounts first if needed, then `thunar <mountpoint>`,
    detached), Mount / Unmount, Eject (unmount each mounted volume, then `power-off`).
    Errors show udisksctl's reason ("target is busy"). Polkit asks via the shell's agent
    only if a rule needs it.
  - Bar: a USB chip (count when more than one) only while a removable drive is present;
    it opens the `devices` surface, a card per drive with Eject and its volumes.
  - autostart.lua: `udiskie --no-tray --notify` (automount + the "device added" toast
    through the shell's notification server), as the SPEC says.
  - Tests: parser unit tests (internal, USB stick, unpartitioned SD card, hotplug disk
    mounted at /mnt excluded, swap-only, unformatted partition) and the exact
    eject/mount/open commands; phase4 with fake lsblk/udisksctl/thunar: chip only while a
    stick is in, real clicks on the chip, Open (thunar gets the mount point) and Eject
    (unmount then power-off, then chip and card go). Also fixed a harness race: chip
    positions are now read once the bar is fully wide.
- 2026-09-27 - Phase 6.1 (polkit agent), deployed and committed with Suraj's approval. Backup
  `phase6-polkit-20260927-193804` (`UNDO.txt`, `new-files.txt`, `files/`).
  - `PolkitAgent` in shell.qml (both layouts) feeds `components/PolkitDialog.qml`: a dimmed
    full-screen overlay (layer Overlay, namespace `quickshell-polkit`, exclusive keyboard) on
    the monitor focused when the request starts, with a centred card: lock icon, action id,
    message, the identity ("As Suraj", or a choice when polkit offers several; switching
    restarts the conversation), the password field (echo as polkit asks), the failure or
    polkit's own message, Cancel / Authenticate. Enter submits, Escape cancels. It is its
    own window, so it works whether or not the pill is shown.
  - The password leaves the field on submit, cancel and when the request ends. The field is
    disabled while polkit checks; focus returns to it whenever polkit asks again.
  - Quickshell registers the agent once, at startup, with no retry; a warning is logged if
    it is not registered 5 s later (another agent holding the session).
  - Live: `pkexec true` (wrong password shows the error and retries, then succeeds; Escape
    cancels) and `systemctl restart systemd-timesyncd` all used the new prompt (polkitd and
    pam in the system journal agree). virt-manager shows no prompt by design: Suraj is in
    the `libvirt` group and libvirt's `50-libvirt.rules` grants `org.libvirt.unix.manage`
    without a password. GParted is not installed.
  - `polkit-kde-agent` removed from autostart.lua (separate commit) once this worked; the
    package stays in desktop-core.txt as a fallback until Phase 8. Only one agent now
    registers per session (before, both started at login and raced).
  - Tests: phase4 drives the dialog with a fake AuthFlow on Xvfb (real keyboard and
    pointer): field focused on open, Enter submits and clears, failure shown and retried,
    identity switch by click, Escape cancels; statically: layer, namespace, exclusive
    keyboard, exactly one agent in shell.qml feeding the dialog.
- 2026-09-27 - Phase 6.2 (Wi-Fi and Bluetooth surfaces), deployed and committed with Suraj's
  approval. Wi-Fi verified live (inline password connect works). PENDING live test (Suraj,
  later): pair a new Bluetooth device from the surface. Backup
  `phase6-netbt-20260927-132453` (`new-files.txt`).
  - `network` surface (bar Wi-Fi icon; in frame mode also the System view's Wi-Fi tile):
    power switch, rescan (every 20 s while open), list (connected first, then signal),
    and a card for the selected network: inline password (8-63 characters or 64 hex;
    Enter connects, eye shows it), Connect / Disconnect / Forget, failure reason (wrong
    password, timeout, network lost). The list is rebuilt on every signal change while
    scanning, so the password field is in the card, never in a row.
  - `Net.connectPsk` uses `WifiNetwork.connectWithPsk`; if a new profile fails, it is
    forgotten so the next try asks again (a saved network that fails keeps its profile).
    Enterprise (802.1X) networks show a pointer to nmtui.
  - Hidden networks: `Quickshell.Networking` cannot see them, so `nmcli --ask --wait 45
    device wifi connect <ssid> hidden yes`, argv only (no shell), and the password is
    written to stdin, never argv (other processes can read argv from /proc). Stdin closes
    after that one answer, so a second prompt (wrong password) fails at once; checked with
    a real Process.
  - `bluetooth` surface (bar Bluetooth icon; the System view's Bluetooth tile in frame
    mode, which no longer toggles power directly: the switch is in the surface): power,
    scan (30 s, again every 25 s while open), devices (connected, paired, then by name;
    unnamed unpaired devices hidden), battery % when reported; Pair and connect (pair,
    then trust, then connect), Connect, Disconnect, Forget.
  - No BlueZ pairing agent (none runs, and Quickshell 0.3.1 has no agent API): devices
    that need a PIN or passkey confirmed cannot pair here; use `bluetoothctl`.
  - Classic mode unchanged: its System view keeps the network drill-in (and the terminal
    fallback for new secured networks) and the Bluetooth power tile.
  - `SurfaceButton.qml`: the updates surface's button, now shared by the three surfaces.
  - Hover feedback (Suraj: some icons were hard to click and had no highlight): the bar's
    Wi-Fi, Bluetooth and update chips are `BarChip`s (24 px minimum target, rounded hover
    background, accent, 1.08 scale); every other bar chip (clock, volume, mic, Caffeine,
    Game Mode, notifications, System, power) gets the same background via `ChipHighlight`
    in PillBar, whose padding also takes the click (mic: highlight only, its mute click is
    internal). The shared chip components are untouched, so the classic bar is unchanged.
    In the surfaces: `SurfaceIcon` (28 px, rescan and show-password) and `SurfaceSwitch`
    (hover ring), and "Hidden network" is a full-width row. The refresh icons spin (Suraj: "not just
    static"): Bluetooth for its real 30 s discovery; Wi-Fi for 3 s after each requested scan
    (NetworkManager keeps scanning while the surface is open, so there is no end to follow).
  - Caffeine always in the expanded bar (Suraj): the chip stays, dimmed while off, click
    toggles (`Caffeine.qml` gains `on`, default true, so classic still shows it only while
    active). The System view already had its Caffeine tile; 6.5 Settings lists it too.
    CPU/RAM readouts now hide on bars under 900 px, so the right-hand chips never reach
    the centred clock (the phase4 800 px screen caught the overlap); real bars are 1200 px.
  - Keyboard trouble and "freeze" after the Caffeine deploy (boot -1, 2026-09-27): not the
    shell. The Moonlander (usb 7-6.1.1.3, on the CalDigit TS4 dock's hub 7-6.1.1) reset at
    15:07:11 and never answered again (descriptor read -110); the dock's rear audio vanished
    at the same instant (PipeWire front:6p). It survived the reboot: at 15:12 the Moonlander,
    the dock's rear audio (7-6.1.1.4) and 7-6.1.5 still failed (-110/-71) until 15:18, so
    the dock's hub itself was wedged (a reboot does not power-cycle the dock). The earlier
    shell restarts that day (same ddcutil probe) had no USB errors; autosuspend is off for
    the devices and no power daemon runs. The burst of `qs` processes in the journal was the
    phase4 harness polling its private test shell (it now sets LC_ALL=C.UTF-8 like phase0,
    so it no longer logs locale warnings). Backups under `phase6-netbt-20260927-132453/`
    (`pre-hover/`, `pre-chip-highlight/`, `pre-caffeine/`) kept in case it recurs.
  - Tests: unit tests for passphrase rules, new vs saved profiles, an invalid password
    never reaching NetworkManager, hidden SSID password only on stdin, Bluetooth order,
    battery, unnamed devices, pair before connect. phase4: both surfaces open at 400 px,
    and real clicks on the System tiles open them. Live: both render with real networks
    and devices, clean log.
- 2026-09-26 - Phase 6.4 (update notifier), deployed and committed with Suraj's approval (after a real
  upgrade through the Update button, the recheck cleared the official and Flatpak counts). Backup
  `phase6-updates-20260926-234859` (`new-files.txt`).
  - `services/Updates.qml` singleton: one read-only check 90 s after start, hourly, and on
    demand (`qs ipc call updates check`; `updates status`): `checkupdates`, `flatpak
    remote-ls --updates --columns=application`, `paru -Qua` when paru exists, each under a
    120 s timeout. Exit codes per tool (checkupdates 2 = none, paru -Qua 1 with no output =
    none); a failed source (offline, timeout) is "unknown", not zero, and keeps its last
    good count. Verified live: checkupdates used its own database (`pacman -Qu` on the
    real one still said 0 afterwards).
  - Bar: an update badge (cloud icon + total) before the power button, only when something
    is waiting; it opens the small `updates` surface: total, when it last checked, counts
    and the first package names per source, "Check now" and "Update".
  - Update opens a floating ghostty running `paru` (or `sudo pacman -Syu` without paru),
    then `flatpak update` only when Flatpak has updates (the SPEC named only paru; paru does
    not update Flatpaks), then `qs ipc call updates check` so the badge clears. Nothing
    upgrades except that button.
  - First live check: 12 official, 18 AUR, 13 Flatpak. The AUR count includes -git
    packages paru reports as "latest-commit" (its devel check), and Flatpak counts runtimes.
  - Found by the new integration test: a JavaScript automatic-semicolon trap (a line
    starting with `[` after `var r = root.parse(text)` became an index expression); fixed,
    and no other code has that shape.
  - Tests: unit tests for parsing (each tool's exit codes, absent tools, failures unknown,
    empty output) and the update command; phase4 stubs the three tools (logging every call)
    and checks counts and names, the badge, the surface, and that only the three read-only
    commands ever ran.
- 2026-09-26 - Phase 5.2 (keybind cheatsheet), deployed and committed with Suraj's approval. Backup
  `phase5-cheatsheet-20260926-222209` (`new-files.txt`; `files/hypr/binds.lua` and
  `binds.lua.pre-labels`).
  - `components/pill/surfaces/Cheatsheet.qml`, the pill's `cheatsheet` surface (920x520,
    clamped to the bar and the screen height; opens centred): `hyprctl binds -j` read on
    every open, modmask bits decoded (SPEC 5.2), key names made readable (Enter, arrows,
    Scroll up/down, Left/Right drag, Vol +, Mic mute; double-tap Super shows "Super x2"),
    grouped by the description prefix into three columns balanced by size (biggest groups
    first, each column in the original order). Typing filters by text, keys or group;
    Escape closes; typing needs the exclusive keyboard focus the launcher already uses.
  - Super+/ (`qs ipc call pill toggle cheatsheet`, an allowed §4.2 addition) toggles it; the
    launcher has a `> Keybind cheatsheet` action (`runShellAction("cheatsheet")`).
  - Every bind in binds.lua has a description (Media / Screenshot / Apps / Windows /
    Workspaces / Session / Shell). In this Hyprland every bind reports as `__lua` with an
    opaque function id, so the description is the only readable text. Suraj approved the
    label on the frozen Gaming Mode key (Super+Shift+S); key and command are unchanged.
    The Phase 0 guard strips description labels and still compares keys and commands byte
    for byte (checked: changing a command fails it), and it requires a description on
    every bind. Live: 53 of 53 binds described, the parser run on the live list gives 7
    groups and no "Other".
  - Classic has no pill, so Super+/ does nothing there.
  - Tests: unit tests for modmask decoding, key labels, grouping (double-tap, no
    description, no prefix), filtering and column balance (including the live group sizes);
    phase4 opens the cheatsheet on Xvfb with a stubbed `hyprctl binds -j` (the stub still
    fails every other hyprctl call): size, groups, keyboard filter, Escape, reopen
    unfiltered, Super+/ toggle. Previewed at 1920x1080 with the live binds; four long
    labels were shortened so none elide.
- 2026-09-26 - wofi removed from the repo with Suraj's approval: `.config/wofi` (config,
  style.css) and its entry in `scripts/bootstrap-arch.sh`. The live `~/.config/wofi` and the
  installed wofi package are left alone (`sudo pacman -Rns wofi` if wanted).
- 2026-09-26 - Phase 5.1 (launcher + clipboard), deployed and committed with Suraj's approval. Backup
  `phase5-launcher-20260926-212413` (`new-files.txt`; `files/hypr/binds.lua`).
  - `components/pill/surfaces/Launcher.qml`, the pill's `launcher` surface (640x470,
    clamped to the bar; opens centred). Modes by prefix: apps (the classic launcher's search
    over name / generic name / keywords, starts-with first, categories; Tab cycles them; a
    GridView keeps the selection in view), `=` calculator, `>` actions; clipboard mode is
    opened by Super+V. One search field; arrows move, Enter runs, Escape closes.
  - Calculator: `qalc -t -- <expr>`, 140 ms debounce, Enter copies via `wl-copy` (never a
    stale result). Deviation: no `-e` - in qalc that is `--exrates`, a download of exchange
    rates on every calculation (checked in qalc(1)). Missing qalc shows "install
    libqalculate" (it is in desktop-core.txt but was not installed; Suraj installed it).
    Checked with the real qalc 5.12: `--` handles a leading minus, currency conversions use
    the bundled rates without prompting or downloading (auto_update_exchange_rates=-1),
    errors (e.g. "20% of 80") show "No result". qalc prints U+2212 for minus, so the copy
    replaces it with "-"; the hint shows "80 * 20%", which qalc accepts.
  - Actions: gaming, gamemode, caffeine, nightlight, dnd, wallpaper, overview, screenshot,
    lock, suspend, logout, reboot, poweroff -> `runShellAction(id)` in shell.qml, reusing the
    existing processes / IPC handlers. Log out, reboot and power off need a second Enter
    within 3 s (the row turns red). Actions run once the surface has closed, so a screenshot
    never catches it. `cheatsheet` arrives with 5.2.
  - Clipboard: `cliphist list`; Enter runs `printf '%s' "$line" | cliphist decode | wl-copy`;
    Delete (cursor at the end of the search) or middle-click runs `cliphist delete`; typing
    filters. Image entries get a thumbnail decoded lazily (visible rows only) into
    `$XDG_RUNTIME_DIR/quickshell-clip/` (tmpfs, cleared at logout).
  - Super+V: `qs ipc call launcher clipboard` replaces the wofi pipeline in binds.lua (same
    key). The Phase 0 bind guard allows exactly this one command change. Over an open
    launcher it switches to the clipboard; again closes. Super+Space unchanged
    (`launcher toggle`), now the pill surface in frame mode. The launcher layer takes
    keyboard focus exclusively while open (the other surfaces stay on-demand).
  - Classic keeps its old launcher overlay (created only in classic now); classic has no
    clipboard view, so `launcher clipboard` only logs a warning there.
  - wofi: no longer used. Its config dir `.config/wofi` and the bootstrap link to it remain
    until Suraj approves deleting them.
  - Found live: `SoundView`'s FastBlur got a null source while album art loaded, so every
    track change logged "ShaderEffect: Texture t1 is not assigned a valid texture provider"
    (twice: one Sound view per monitor, since 4.3). Its source is now always the art Image.
  - Tests: unit tests for app filter/ranking/categories, actions filter and cliphist
    parsing. phase4 drives the real launcher by keyboard on Xvfb with stubbed qalc, cliphist
    and wl-copy: 640x470 clamped, app search and launch, calculator args and copy, two-Enter
    destructive actions and 3 s expiry, one-Enter caffeine, clipboard list / thumbnail /
    Delete / filter / copy, Super+V switch and toggle, Escape. Live: clean restart, no
    config errors, bind set unchanged apart from Super+V's command, `launcher clipboard`
    opens and closes on the focused monitor.
- 2026-09-26 - Frame is the default layout (Suraj). `Config.appearance.layout` is "classic"
  only when set to exactly that; missing or invalid values now mean frame. Fresh installs
  and the repo's `settings.json` (no `appearance` section) get the frame; Suraj's live
  settings already said frame, so nothing changed on screen. Deployed, backup
  `phase4-frame-default-20260926-210334`. Tests: phase4 now starts from an explicit classic
  file (frame would pass either way, hiding the startup-read regression), then checks that
  the default, invalid values and removed sections give frame, and that classic still
  works when asked for.
  Phase 4 acceptance still open, deferred by Suraj to run himself later:
  - a fullscreen game or `mpv --fs`: `hyprctl layers` shows no Quickshell surface on that
    monitor, and VRR/tearing still engage (MangoHud / `hyprctl monitors`);
  - the Gaming Mode round-trip (§7.3);
  - dock audio after a suspend (earlier open item).
- 2026-09-26 - Phase 4.5 (edge drawers), deployed and committed with Suraj's approval. Backup
  `phase4-drawers-20260926-205136` (`new-files.txt` lists the two files that were absent).
  - `components/pill/EdgeTab.qml`: a drawer joined to the frame, drawn like the pill (one
    path in `frameBg`, running into the frame edge, concave shoulders). Two forms: a tab out
    of the right edge, and a drawer in the top-right corner joined to both edges.
  - `components/pill/Drawers.qml`, hosted by `PillOverlay` (so both hide with it on
    fullscreen, SPEC 3.1): toasts in a 392 px corner drawer (`notifDrawerWidth` 360 plus the
    toast margins) that grows with the stack (morph timing) and closes with the last toast;
    they are the classic `NotificationToasts` cards, so timeouts, dismiss, media art, the
    4-toast cap and DND behave as before (it now reports its `implicitHeight`). The OSD is a
    52x220 tab from the right edge, vertically centred, on the focused monitor only, hidden
    2 s after the last change; it shows volume (and mute), mic mute (the `XF86AudioMicMute`
    key; new, the classic OSD had volume only) and brightness (the System view slider).
    Same change rules as the classic OSD: never on the first reading.
  - Input: the toast drawer joins the pill's input mask (its close buttons work); the OSD
    stays click-through. Motion follows `appearance.animations` / Game Mode like the pill.
  - `shell.qml`: the classic OSD and toast windows are only created in classic mode.
  - Deviation to note: in frame mode toasts do not show over a fullscreen window (the
    overlay is unmapped there, SPEC 3.1); they still reach the history (Notifications
    surface) and the badge. Classic showed them over fullscreen apps.
  - Tests: phase4 adds toasts (corner position, 392 px, grows and settles, max 4, timeout,
    dismiss closes the drawer, shape pixels: top and right-edge shoulders, rounded corner),
    the OSD (52x220 at the right edge, centred, shape pixels, hides after 2 s, mic kind),
    both hidden on fullscreen, and a static check that frame mode creates no classic
    OSD/toast windows. Live: clean restart, no warnings, binds unchanged, a real
    `notify-send` toast raised no errors; no `quickshell` classic windows in `hyprctl layers`.
  - 4.4 review (before 4.5): SPEC 3.2/3.4 still described now-playing in the bar; updated.
    Stale "now-playing" comments in `PillOverlay` and the phase4 harness corrected. The
    4.4 commit body (`36a90e0`) still lists now-playing as a dashboard opener; it was
    removed in the same commit (the SPEC entry below is right).
- 2026-09-26 - Phase 4.4 (dashboard), committed `36a90e0` with Suraj's approval.
  `components/pill/surfaces/Dashboard.qml`, a 920x420 surface (clamped to the bar on small
  screens) with Dashboard / Media / Performance / Weather tabs. Opens from the clock (Dashboard
  tab), from now-playing (Media tab; the tier grows from whichever was clicked) and Super+D,
  which toggles (spec said open; toggle lets the same key close it). IPC open/toggle accept
  dashboard and media. Opening from the rest tab now widens the bar first and only then
  raises the tier, mirroring the close fix, so no surface slides while the bar resizes.
  Dashboard tab: user card (initial when ~/.face is absent, as here; ~/.face is watched and
  loaded only if it exists), uptime and kernel from /proc, current weather, a Monday-first
  month calendar with navigation, media card with art and controls. Media tab: large art,
  details and controls. Performance: CPU (Sysmon), RAM (Sysmon), the GPU driving a connected
  display (found at runtime: the RX 9070 XT, card1; busy %, edge temperature, VRAM) and `/`
  (df), read every 2 s / 30 s only while that tab is shown. Weather: current details and the
  forecast. Deviations: wttr.in's JSON has 3 forecast days, not 7; cava bars skipped (spec:
  optional). Fixed in the shared Weather service: U+F6C4 ("partly cloudy") has no glyph in
  the installed Nerd Font, and the rain range was checked before snow/thunder (patchy snow,
  blizzard and thundery outbreaks showed rain; snow showers fell through to a cloud). Now
  one Weather Icons set (U+E3xx, verified rendered) with specific codes first; the classic
  clock popup benefits too. Checks: phase0/phase3 pass; phase4 x3 adds dashboard open from
  rest (tier waits for the bar), size/clamp, clock vs now-playing tabs, toggle and switching;
  unit tests for uptime, df parsing, GiB and the calendar offset; visual render of all four
  tabs at 1920x1080 with real CPU/GPU/disk readings, no QML errors. Live backup
  `phase4-dashboard-20260926-144754`.
  Feedback round (Suraj: Spotify and YouTube usually play together, Spotify should be the
  main one; media name and dashboard not centred; look at the UI). Deployed, backup
  `phase4-media-20260926-150432`:
  - Media service: `ordered` = Spotify first (identity or desktop entry), then playing, then
    the rest (stable), used by the bar and the dashboard. `playerctld` (a proxy that mirrors
    the active player, found live as a second "Spotify") is filtered out; the Sound panel's
    duplicate Spotify tab goes with it.
  - Dashboard: Spotify is the main player even when paused; other players are listed ("Also
    playing" on the Media tab with art, title and play/pause; chips on the Dashboard tab's
    media card); a click makes one the main player until the dashboard closes. Media tab is
    centred with a seekable progress bar and times; the media card has progress too; the
    weather card shows the forecast days. The dashboard opens centred on the bar.
  - Bar: now-playing sits at the true centre (elided to the room between the title and the
    right-hand items) and prefers Spotify when it plays. Found while checking: the tray is a
    nested RowLayout, which fills by default, so since 4.2 it split the free space with the
    spacer and parked CPU/RAM in the middle of the bar (now `Layout.fillWidth: false`).
  - Clock, not the track name, sits at the bar's centre (Suraj: the media name was redundant
    beside the Media tab and the media keys, and the clock is what a centred slot should
    hold). Clicking it still opens the dashboard; the Media tab stays reachable from the
    dashboard and `qs ipc call pill open media`. The bar title stops short of the clock.
  - Tests: phase4 adds a second run on a private bus (scripts/tests/private-bus.conf: no
    service activation, so no portals/gvfs get started) with two fake MPRIS players
    (scripts/tests/fake_mpris.py: Spotify paused, Firefox playing): Spotify main, Firefox
    listed, choosing and reset, now-playing shown and clear of the row; the harness now
    asserts only the spacer stretches. Unit tests for ordering, the playerctld filter and
    track times. A first probe used a default private bus, which activated real portal/gvfs
    services on that private bus; they exited with it (verified: only the login-session
    processes remain) and three orphaned test helpers were stopped by PID.

- 2026-09-26 - Phase 4.3 (surfaces), deployed with Suraj's approval; confirmed by Suraj
  (panels, close in place, and Caffeine under the new Background-layer inhibitor window).
  Sound / Notifications / System now open inside the pill: a 400 px tier (the views keep
  their classic 380 px content) rises from the bar row above the chip that opened it
  (Suraj: growing from the centre felt wrong), kept 38 px (corner + join radius) inside the
  bar's ends; on a 1200 px bar the right-hand chips all land at that clamp, i.e. where the
  classic panel hung under them. Drawn as part of the
  same ShapePath (radius-26 corners, concave joins into the bar top); 420 ms morph, content
  fades in over the last 40%. The bar row stays underneath, so its chips switch surfaces
  directly or close the open one (same chip again). Escape (keyboard focus on demand only
  while a surface is open), a click elsewhere (HyprlandFocusGrab, as the classic panel) and
  IPC close it; a surface never auto-collapses; fullscreen changes close it. IPC `pill`
  open/toggle accept sound / notifs / system. The notification badge now clears only when
  Notifications opens (the classic panel cleared it for any tab). The overlay window is now
  full-height (spec 3.1) but its input mask stays pill + tier + hot strip; no backdrop.
  Frame mode no longer creates the classic top bar: the frame reserves its top edge again
  (reserved [10, 10, 10, 40] live). Caffeine's idle inhibitor moved to a 1x1 invisible
  Background-layer window (quickshell-inhibitor), mapped even under fullscreen; classic mode
  keeps the bar's. The 4.2 bridge to the classic panel is gone. The clock's calendar/weather
  popup is not in frame mode until the 4.4 dashboard.
  Checks: phase0/phase3 pass; phase4 x3 adds surface open/switch/toggle, Escape, stay-open,
  badge, fullscreen close and tier shape pixels; visual render of all three surfaces at
  1920x1080, no QML errors. Live backups `phase4-surfaces-20260926-141817`,
  `phase4-surface-anchor-20260926-142821`, `phase4-surface-close-20260926-143208`.
  Closing fix (Suraj: it jumped to the middle before closing): the tier keeps the last
  surface's chip as its anchor while it shrinks, and the bar stays wide until the tier has
  fully closed, so neither slides; phase4 asserts the tier x is unchanged while closing.
- 2026-09-26 - Phase 4.2 live feedback from Suraj, fixed and deployed (backups
  `phase4-pill-20260926-111731`, `phase4-pill-timing-20260926-114821`).
  1. A peek never hid: it waited for the pointer to visit first, which over a game it rarely
     does. A peek now hides 800 ms after it opens whenever the pointer is not on it.
  2. Collapse felt too aggressive: the 6 px frame band between the bottom hot strip and
     the pill counted as "outside", and 300 ms was short. The band and shoulders now count
     as the pill (input mask + HoverHandler), and the delay is 700 ms by default
     (deviation from §5.2's 300 ms), tunable live via `pill.collapseDelayMs` (global or
     `monitors.<name>.pill`, integer 0-5000; invalid values fall back).
  phase4 check covers the frame band, the untouched peek and the delay setting.
- 2026-09-26 - Phase 4.2 (pill), repository only; not committed or deployed.
  `components/pill/`: PillOverlay (one per screen, Overlay layer, namespace quickshell-pill,
  bottom-anchored 56 px window that never resizes or reserves; input mask = pill + a 4 px
  bottom hot strip that only hovers), PillShape (pill + concave shoulders as one ShapePath,
  filled down through the frame edge; shoulders shrink to fit the 30 px tab), PillBar (rest:
  workspace dots + clock; hover: the SPEC 3.4 row reusing the existing chips, scroll on
  workspaces switches; cross-fade driven by the animated height). States rest / hover /
  hidden: 150 ms edge dwell, collapse 300 ms after leaving (800 ms when peeking), IPC or
  click pins until the pointer has visited and left, fullscreen unmaps it and a pin is the
  peek, fullscreen changes end a peek. `pill.hoverExpand` (global or per monitor) = false
  gives rest-only / click to expand; the repo settings.json sets it for HDMI-A-1 (§8.3).
  `appearance.animations` and Desktop Game Mode zero the morph. IPC `pill`: peek, open,
  close, toggle, status (surface names are accepted but open the bar row until 4.3/4.4).
  Double-tap Super: counted in binds.lua (§4.2, §8.2); the Phase 0 guard now allows only
  the §4.2 binds, appended after a marker, and existing binds must stay byte-identical.
  Preview bridge (ponytail-marked): the pill's Sound/Notifications/System chips open the
  classic panel on the same screen until 4.3; the classic top bar stays in frame mode.
  TrayArea gains `menuEdge` so pill tray menus open upward. Frame reserves the rest tab again.
  Checks: phase0/phase3 pass; phase4 (3 consecutive runs) adds a real xdotool pointer on
  the private Xvfb: rest geometry and shape pixels, edge pass-through vs dwell, collapse,
  IPC pin/toggle, fullscreen hide + peek, rest-only click, animations off; the harness now
  stubs session commands like phase3. Lua test drives the real binds.lua tap counter with a
  fake `hl` (single, double, slow, triple/quadruple taps). Visual check on a 1920x1080 Xvfb:
  row layout fits 1200 px; isolated shape render shows the rounded corners and shoulders.
- 2026-09-26 - Phase 4 decisions (§8 1-3) settled with Suraj before 4.2: tab rest style,
  hover dwell + double-tap Super (replaces `Super+grave`, see §8.2 for the live test),
  HDMI-A-1 rest-only / click to expand. The temporary test bind was runtime-only and is gone;
  binds match the pre-test set (the Super+arrow binds only changed internal Lua function IDs,
  because binds.lua registers them with `pairs()`, whose order varies between reloads).
- 2026-09-26 - Fixes found while previewing frame mode live, deployed; not yet committed.
  1. Config ignored settings.json at startup (since Phase 3 slice 1): the file was read, but
     JsonAdapter's own `({})` defaults overwrote it, so values applied only after the file
     next changed. Unnoticed because Suraj's values equal the defaults. Config now parses the
     file text directly and synchronously (no JsonAdapter): missing file = defaults, malformed
     save keeps the last good values (now logged), deleted sections fall back to defaults.
     Regression: phase4 check starts with a settings file present.
  2. Side effect guarded: Config now rebuilds its objects on every edit, which re-triggered
     DDC reads (and cleared errors) and could rebuild frame windows. Brightness reacts to a
     string key of the bus map; shell.qml uses a `frameLayout` bool. Phase4 asserts that an
     unrelated edit does not rebuild frames.
  3. Frame preview beside the classic bar: no top reserve (the bar already reserves the
     top) and no empty pill space at the bottom until 4.2 (bottom reserve = 10 px). The bar
     moves down by the frame thickness; side reserves already inset it horizontally.
  Live: reserved [l,t,r,b] = [10, 50, 10, 10] on both monitors; bar 22 px from the sides and
  18 px from the top. Backups `phase4-frame-fix-20260926-093416`,
  `config-startup-fix-20260926-094059`. No runtime warnings; keybinds unchanged.
- 2026-09-26 - Phase 4.1 (frame + reserves), deployed (classic default) with Suraj's approval.
  Gaming Mode round-trip deferred to final acceptance at Suraj's request (still required).
  `Config.appearance.layout` = "classic" (default; any invalid value) | "frame". Classic
  creates no extra windows. Frame mode adds, per screen, `components/frame/Frame.qml`
  (Top layer, namespace quickshell-frame, empty input mask, no keyboard focus, ignores
  reserves so it draws at the physical edges; odd-even ShapePath with frameRadius inner
  corners) and four `Reserve.qml` strips (empty masks, fixed exclusive zones: 10 px
  top/left/right, bottom 10 + rest height = 40 tab / 16 handle). Rest style comes from
  `Config.pillFor(monitor)`: `monitors.<name>.pill.restStyle` overrides `pill.restStyle`;
  invalid values fall back to "tab". Frame and reserves hide on per-monitor fullscreen.
  Tokens added to Theme: frameBg, frameThickness, frameRadius, pillRest{Tab,Handle}Height.
  `gaps_out` left at 11: already ~12 px inside the frame, so no Hyprland change.
  Deviation: the classic top bar stays in frame mode until the pill (4.2/4.3) takes over
  its controls and the Caffeine inhibitor surface; frame mode is a preview until then.
  Checks: new `scripts/check-desktop-phase4.py` runs on a private Xvfb (Quickshell has
  no offscreen PanelWindow backend); classic default, switch/reset, invalid settings,
  reserve zones/anchors/masks/focus, per-monitor fullscreen, hotplug, rest-style overrides,
  and frame pixels (opaque edges, transparent interior, rounded corners). Layer-shell
  properties are checked statically (Xvfb has no layer shell). Not tested offline: live
  Wayland exclusive zones, click-through, direct scanout/VRR. phase0/phase3 still pass.
  Live backup `phase4-frame-20260926-090052`. Restart verified in classic mode: identical
  layer namespaces to before (no frame surfaces), no new runtime warnings, keybinds and
  Hyprland config unchanged, notifications on Quickshell, Caffeine restored to on.
  Pending: Suraj previews frame mode live (placement, click-through, fullscreen hide).
- 2026-09-26 - Review follow-up, commit/deployment approved by Suraj; deployed.
  The previous Phase 3 completion report overstated acceptance: the service extraction
  was finished, but visual checks and the Gaming Mode round-trip are still outstanding.
  Brightness review found dropped drag updates while Process was running, invalid/partial
  display blocks accepted as usable buses, bus zero ignored, and missing Config overrides.
  Regression tests reproduced the detection bug. Brightness now serializes I/O, keeps
  the latest queued slider value, reads back after the final write, propagates command
  failure (including one monitor failing), and validates direct getvcp output instead of
  hiding errors behind awk/wait. No new polling. Unavailable/error states are visible.
  Config now validates optional brightness.buses overrides; deleting them restores auto
  detection. Corrected the reversed bus mapping in the settings example (not just this log).
  Checks: phase0 and expanded phase3 harness; stubbed slow writes, coalescing, partial
  failure/recovery, malformed/failed reads, override/reset, and pure parser/input tests.
  Live backup: `phase3-review-20260926-082625`. Copied only Brightness.qml, Config.qml
  and SystemView.qml, then restarted Quickshell. Verified: live files match the repo,
  no new runtime warnings/errors, desktop IPC healthy, notifications owned by Quickshell,
  keybinds unchanged and no Hyprland config errors. Restored the pre-restart Caffeine
  setting (on). Read-only detection confirmed HDMI-A-1 bus 8 and DP-2 bus 10.
  No brightness write, network toggle, suspend or Gaming Mode transition was run live.
  Next gate: visually verify controls, then run §7.3 while Suraj is present. Only then
  start 4.1 behind the default-classic layout switch.
- 2026-09-25 — Phase 3 slice 3c (Brightness), deployed with Suraj's approval.
  `Brightness` singleton owns ddcutil. `ddcutil detect --brief` runs once at startup and maps
  DRM connector → I2C bus (verified live: HDMI-A-1→8, DP-2→10), so the hardcoded 8/10 in
  SystemView go away. Read still samples one monitor's brightness (first detected bus; was
  bus 8 = HDMI-A-1), and the single slider still sets every detected monitor, so behaviour is
  unchanged until Phase 4 adds per-monitor controls. SystemView now binds `brightness` to the
  singleton and delegates read/set to it. Checks: phase0/phase3 pass; parseDetect is unit
  tested (real ddcutil output + a partial-entry rejection); the harness stubs ddcutil (detect,
  getvcp→28%, setvcp no-op) and asserts the detect→read path resolves both buses.
  Live backup `phase3-brightness-20260925-230602`. Restart verified: no new log warnings,
  desktop IPC and notifications fine, keybinds unchanged, live brightness still 100%.
- 2026-09-25 — Phase 3 slice 3b (Net/Bt), deployed with Suraj's approval.
  Before: the System tab polled nmcli + bluetoothctl every 2 s while open and every 10 s
  always (one timer per monitor), plus 3 nmcli processes per network-list refresh. `Net`
  (Quickshell.Networking, NetworkManager over D-Bus): wifiEnabled switch, connected SSID,
  network list in the old item shape (connected first, then signal; hidden networks
  dropped; Open → no label, else "WPA2"/"WPA3"…), native `connect()` for known/open networks,
  scanner on for 30 s per scan (kept on while the list is open). Fixed as a side effect:
  SSIDs containing ':' were split by the `nmcli -t` parser. New secured networks keep the
  terminal fallback (`ghostty -e nmcli … --ask`) until the Phase 6 password prompt; SSIDs are
  untrusted, and the sh-quote + JSON/Lua string path is unit-tested with a hostile SSID
  (arrives as one argument). Known edge: an SSID with control characters makes the Lua string
  invalid, so that connect fails safely. `Bt` (Quickshell.Bluetooth): adapter power only; the
  device list waits for the Phase 6 UI. Checked live (read-only probe): 4 NM devices, wlan0
  connected at 72%, adapter "arch" enabled; values arrive ~1 s after start.
  Brightness unchanged (read on tab open; slice 3c). Checks: phase0/phase3 pass; the harness
  now also requires the Networking "no backend" error as proof that D-Bus stayed unreachable.
  Live backup `phase3-netbt-20260925-225755`. Restart verified: no nmcli/bluetoothctl/wpctl/
  pactl process over 12 s (old timer fired every 10 s), no new log warnings, desktop IPC and
  notifications fine, keybinds unchanged, Wi-Fi/Bluetooth state unchanged by the restart.
- 2026-09-25 — Phase 3 slice 3a (Audio), deployed with Suraj's approval.
  Measured before: ~8 wpctl processes/second all the time (Volume chip 1 s, OSD 0.5 s, Sound
  tab 1 s; one each per monitor) plus 7 pactl calls per Sound-tab refresh. `Audio` now uses
  Quickshell.Services.Pipewire: default sink/source volume and mute, sink/source lists
  (PwNodeType AudioSink/AudioSource = pactl's sinks and non-monitor sources, checked live),
  per-app playback streams (AudioOutStream = pactl sink-inputs), default device via
  `Pipewire.preferredDefaultAudioSink/Source`. Volume scale checked live: identical to wpctl
  (0.29 = 0.29), so percentages don't change; the 150% ceiling is kept. The OSD uses the same
  rule (skip the first reading, then >0.5% or mute) on PipeWire change events, not a 500 ms
  poll. PwNode has no running/idle state, so the device picker's state label still comes from
  one `pactl list short` call when the picker opens (as before), not polling.
  Removed as dead: `defaultSinkDesc`, and UnifiedPanel/SoundView `currentVolume/currentMuted`.
  Microphone.qml already used native PipeWire; unchanged.
  Checks: phase0/phase3 pass; unit tests run the real Audio functions against fake nodes and
  the OSD rule; the harness loads Audio with PipeWire unreachable (its connect error is
  asserted, proving isolation). qmllint 584 → 574, no new warnings.
  SPEC correction (§6 Phase 3 settings example): `ddcutil detect --brief` shows DP-2 on I2C
  bus 10 and HDMI-A-1 on bus 8 (the example had them the other way round). Current code sets
  both buses together, so nothing was visibly wrong; fixed properly in slice 3c.
  Live backup `phase3-audio-20260925-222822`. Restart verified: no wpctl/pactl process in
  50 samples over 5 s (was ~8/s), no new log warnings, desktop IPC and notifications fine,
  keybinds unchanged, volume and default sink/source unchanged by the restart.
- 2026-09-25 — Phase 3 slice 2 (Notifs/Media/Weather/Sysmon), deployed with Suraj's approval.
  `Notifs`: NotificationServer (keepOnReload), toast/history models, unread count, DND,
  dismiss/clearAll moved verbatim out of ShellRoot; shell.qml keeps only the DND↔Desktop wiring.
  `Media`: controllable-player list (same filter) and track-change detection; the toast is
  built in Notifs. Unchanged: media toasts still show under DND and stay out of history. Each
  monitor's Sound tab still picks its own player. `Weather`: one wttr.in fetch for all
  monitors (was one per bar); location from `settings.json` `weather.location` (default London,
  trimmed, ≤100 chars), URL-encoded as a single curl argument; refetches on change.
  `Sysmon`: /proc/stat and /proc/meminfo via FileView every 3 s (was bash+vmstat+free while
  the drawer was open); same CPU/memory meaning. Bug fixed: the temperature came from
  thermal_zone0, which here is the Wi-Fi card (iwlwifi); it now reads the CPU package
  sensor by hwmon name (k10temp Tctl / coretemp / zenpower), falling back to the old zone.
  GPU temperature not exposed yet (no consumer until the Phase 4 dashboard).
  Component interfaces unchanged (NotificationToasts test untouched). Checks: phase0 and
  phase3 pass; the harness now also runs Notifs (cap, timeouts, DND, dismiss, clear, media
  toast), Weather (stubbed curl: London, then an encoded "New York" refetch) and Sysmon
  (live /proc and CPU sensor) with no D-Bus, network or compositor. qmllint 599 → 585 warnings.
  Suraj: keep media toasts visible under DND. Live backup `phase3-slice2-20260925-215753`
  (live files matched HEAD, so settings.json was replaced, not merged). Restart verified:
  desktop IPC healthy, Notifications owned by Quickshell, no new log warnings, keybinds
  unchanged, all 12 files match the repo; a real notify-send reached the new service.
- 2026-09-25 — Verified by Suraj in daily use: idle lock and screens-off have fired on their timers
  throughout, and Caffeine holds them off. Still untested: D-Bus ScreenSaver inhibits from apps
  (e.g. Firefox video), which hypridle now owns (2.7). Gamescope round-trip still pending.
- 2026-09-25 — Pre-existing bug found by Suraj during the Phase 3 check: re-clicking a bar chip did
  not close its popup. UnifiedPanel's grab includes the bar, and `open()` never toggled; it now
  closes when the same view's chip is clicked again. BarClock's grab excluded the bar, so the
  click cleared the grab and then reopened; it now includes the bar window (as UnifiedPanel
  does). Clicking elsewhere on the bar no longer closes the calendar (same as the panel).
  Deployed; backup `panel-toggle-20260925-210815`.
- 2026-09-25 — Phase 3 first slice (Config/Desktop/Hypr), deployed with Suraj's approval.
  Registered singletons in `services/qmldir`; moved DesktopServices to `services/Desktop.qml`
  without changing its controller/IPC policy. ShellRoot still owns DND and explicitly binds it
  to Desktop; existing bar/panel consumers share that singleton. `Hypr` now owns the shell's
  focused-monitor lookups and logout dispatch, with a per-monitor fullscreen helper; other
  components' direct Hyprland use remains for later slices.
  `Config` watches `~/.config/quickshell/settings.json` via FileView/JsonAdapter. This slice
  exposes only `idle.lockSec`, `idle.dpmsSec`, `idle.suspendSec` (defaults 600/900/0); zero
  disables a stage. Missing/invalid fields use defaults, malformed JSON keeps the last good
  values, and deleting a section restores defaults. No automatic writes. Other schema sections
  and monitor overrides will be added with their consumers; hyprsunset.conf remains the
  night-light schedule source until then.
  Checks: `python3 scripts/check-desktop-phase0.py` and `python3 scripts/check-desktop-phase3.py`
  pass. The latter exercises real Config/Desktop bindings in offscreen Quickshell with a
  scratch HOME, inaccessible D-Bus/compositor, and stubbed service/helper commands; unit checks
  cover Hypr and the existing Game Mode policy. Qt 6 parsing passes; qmllint still reports
  Quickshell type-metadata warnings. Targeted live backup: `phase3-services-20260925-205658`
  under `~/.local/state/dotfiles-backups/`; retired DesktopServices.qml preserved there.
  Restart verified: desktop IPC healthy (Game Mode status known, no controller error),
  org.freedesktop.Notifications owned by Quickshell, no QML/controller errors, only icon/SVG
  warnings. All six deployed files match the repository; live keybind JSON is unchanged.
  User visual bar/overlay and DND checks, idle/caffeine and Gamescope round-trip remain pending.
  No keybind or frozen-path edits; this slice is not committed yet.
- 2026-09-25 — Task 2.7: hypridle, hooks only (Suraj). `.config/hypr/hypridle.conf` has
  `lock_cmd`, `before_sleep_cmd = loginctl lock-session`, `after_sleep_cmd` dpms on,
  `inhibit_sleep = 3`; no listeners (idle timers stay in DesktopServices.qml). hypridle 0.1.8
  logs `Config has errors: No rules configured` and proceeds; expected. Started from autostart;
  added to desktop-core. It now owns org.freedesktop.ScreenSaver (previously unowned), so app
  idle inhibits reach hypridle, not the shell's IdleMonitor; end-to-end inhibition still needs testing.
  Hyprland `hl.dsp.dpms` treats unknown `action` values as toggle (screens blanked once in
  testing): use only on/off/enable/disable.
  Verified by Suraj: `loginctl lock-session` locks; `systemctl suspend` → hyprlock on resume.
  Found in that test: on resume, three xHCI controllers logged `xHC error in resume … Reinit`,
  and the CalDigit TS4 audio device re-enumerated. Dock audio (default sink) stayed silent
  although PipeWire/ALSA showed RUNNING; restarting pipewire/portal/shell didn't help,
  a reboot did. Root cause and recurrence remain unconfirmed; USB audio re-binding was
  suggested but not tested. Further suspend testing requires Suraj's approval.
- 2026-09-25 — Task 2.5. Removed `.config/{waybar,mako,swaylock,wlogout,kitty,alacritty}` and
  all of `.config/hypr/scripts/` (volume, swww-random-*, plus awww-random-* replaced by
  wallpaper.lua and xdg-portal-hyprland made obsolete by 2.1); no references left. Kept the
  kitty/alacritty window-class matching in QML (icons for those apps) and kitty in frozen
  daily-apps. autostart: `wl-clipboard-history -t` → `wl-clip-persist --clipboard regular`.
  bootstrap copy list trimmed. Live dirs moved to a backup, not deleted (identical to git).
  Suraj removes the packages waybar, mako (its D-Bus service could take the notification name
  while the shell restarts), swaylock-effects-git, wlogout-git.
- 2026-09-25 — Task 2.4. `.config/mimeapps.list`: Thunar, Firefox (web + PDF), Codium (text/code),
  Viewnior (images), mpv (video/audio; Suraj kept current apps), File Roller (archives). mpv and
  viewnior added to desktop-core (extra). `x-scheme-handler/terminal` skipped: Ghostty doesn't
  declare it and nothing here reads it. Live file merged, not replaced (keeps app-added URL
  handlers: Discord, Nexus). bootstrap: runs `xdg-user-dirs-update` (user-dirs.dirs not
  committed: it rewrites missing paths to $HOME); copy list now includes mimeapps.list and the
  folders Tasks 2.1/2.3 added but bootstrap never copied (matugen, qt5ct, qt6ct,
  xdg-desktop-portal). docs/README: kvantum references removed (missed in 2.3a).
- 2026-09-25 — Task 2.3 split (Suraj): 2.3a static base, 2.3b wallpaper colours. Kept breeze-dark
  icons, Adwaita Sans and the cursor (Suraj); Ghostty follows the wallpaper (Suraj).
  2.3a: `GTK_THEME` removed; `QT_QPA_PLATFORMTHEME=qt6ct`; `apply-theme.sh` (autostart) sets
  gsettings `adw-gtk3-dark` + `prefer-dark` and syncs gtk-3.0/settings.ini. qt5ct/qt6ct: Fusion,
  breeze-dark icons. kvantum dropped from desktop-core (unused: qtct palettes suffice).
  2.3b deviation: matugen's input is the shell's neon accent (`matugen color hex <accent>
  -t scheme-vibrant`), not the image; Material dark `primary` from the image was pastel and
  didn't match the bar. GTK/Qt accents use primary/on_primary (contrast-safe); borders and the
  Ghostty cursor use the exact accent. matugen 4.2 needs an empty `[config]` table. Outputs:
  gtk-3.0/gtk-4.0 gtk.css, qt5ct/qt6ct colors/matugen.conf, ghostty/themes/matugen (bg/fg/
  selection/cursor; Cyberpunk ANSI kept), hypr/colors.lua (`pcall(require, "colors")` +
  post_hook `hyprctl eval 'dofile(...)'`; `eval "$(cat)"` fails on the leading `--` comment).
  Apps follow THEME_MONITOR (DP-2). Found and fixed: the 30-min wallpaper rotation never ran
  extract-accent.sh (hyprlock.conf was last written 2026-06-01); it now does. hyprlock keeps its
  existing heredoc in extract-accent.sh (already accent-driven). Verified live: hook updates
  borders, restore exact; scratch-HOME e2e for DP-2/HDMI-A-1 and fresh-install generation.
  Verified after re-login: GTK_THEME unset, portal prefer-dark, rotation recoloured all targets
  unattended; Thunar, Seahorse, qt6ct and launcher icons checked by Suraj (icons improved).
- 2026-09-25 — Tasks 2.1 + 2.2 done. Portals: `modules/xdg_portal.lua` removed; D-Bus/systemd
  activate them. System `hyprland-portals.conf` already routes FileChooser/Settings to gtk, so
  the user file only adds `Secret=gnome-keyring` (it must repeat `default=hyprland;gtk`).
  Correction to 2.1's premise: the systemd user manager outlives logout, and
  xdg-desktop-portal-hyprland dies with the old compositor and hits start-limit. autostart.lua
  now imports the env, then stops + reset-fails the three portal units (D-Bus re-activates on
  first use). Keyring: `gnome-keyring` + `seahorse` installed; `/etc/pam.d/sddm` already had the
  `-auth`/`-session pam_gnome_keyring.so` lines (unmodified, no /etc edits). The package's user
  socket (`gnome-keyring-daemon.socket`) is enabled by preset; start it once if the keyring is
  installed mid-session, or a D-Bus-activated daemon without a control socket blocks PAM unlock.
  No SSH agent (Suraj). KWallet stays as a library dependency (kio, mozillavpn; no data).
  Verified after two real logout/logins: FileChooser dialog opens, all 7 portal interfaces, no
  failed units, `secret-tool store/lookup/clear` with no prompt. Gaming Mode caveat: the return
  path uses a password-less SDDM autologin, so apps prompt once to unlock the keyring.
- 2026-09-24 — Phase 1 done (manifest only, nothing installed). desktop-core.txt:
  quickshell-git→quickshell, matugen-bin→matugen, nordic-theme→adw-gtk-theme,
  dropped grimblast-git, sddm-theme-tokyo-night-git and paru (bootstrap builds it), added
  the Phase 1 table except uwsm (Phase 7) and kdeconnect (skipped by Suraj).
  `scripts/check-official.sh` checks availability in core/extra/multilib via `pacman -Sl`;
  wired into `bootstrap-arch.sh --dry-run` for desktop-core only. Verified: passes on the
  new list, flags exactly the 6 old non-official entries, dry-run exits 0 and writes nothing.
  Locally: matugen-bin→matugen swapped and grimblast-git removed by Suraj. nordic-theme stays
  until Task 2.3 (portal-gtk file dialogs use it); tokyo-night-sddm stays in the SDDM rotation.
- 2026-09-24 — Task 2.6 done early at Suraj's request. `hyprsunset` 0.4.0 installed
  (CachyOS build; also in `extra`). Kept the process model instead of the IPC-toggle
  design above: Night Light on = `hyprsunset` daemon running its schedule
  (`.config/hypr/hyprsunset.conf`: 9:00 identity, 19:30 4000 K), off = daemon stopped.
  Same semantics as the old wlsunset toggle, no shell-side state, survives shell
  restarts. Verified: off/on toggle, profile applied, restart survival. Decision:
  keep the CachyOS Quickshell build (same 0.3.1 source; the manifest rule is that
  every entry exists in core/extra/multilib, not where the local copy came from).
- 2026-09-24 — Phase 0 repository implementation started from clean `362b952`.
  Corrected release/package-source assumptions, live-change/commit approval gates,
  Game Mode restoration and override behaviour, toast callback lifetime, Qt 6 checks,
  Wofi removal ordering and the active paru entry plan. See PHASE0.md for evidence
  and the remaining live tests; later phases are not implemented.
- 2026-09-23 — Initial spec. Package availability verified against archlinux.org
  package pages the same day: quickshell 0.3.1, matugen 4.2.0, awww 0.12.1 (swww was
  renamed to awww), uwsm 0.27.0, hyprland 0.56.2, hyprsunset 0.4.0, xdg-desktop-portal-gtk
  1.15.3, gnome-keyring 50.0, libsecret 0.21.7 (core), qt6ct 0.11, qt5ct 1.9,
  kvantum 1.1.8, kvantum-qt5 1.1.8, adw-gtk-theme 6.5, papirus-icon-theme 20260801,
  wl-clip-persist 0.5.0, xdg-user-dirs 0.20, gvfs-smb 1.60.2, udisks2 2.11.2,
  udiskie 2.6.2, bluez 5.87, libqalculate 5.12.0, pacman-contrib 1.13.1, ddcutil 3.0.1,
  grim 1.5.0, slurp 1.5.0, hyprpicker 0.4.7, cliphist 0.7.0, sddm 0.21.0,
  seahorse 47.0.1, system-config-printer 1.5.18, kdeconnect 26.08.0,
  power-profiles-daemon 0.30, ttf-jetbrains-mono-nerd 3.5.1. Not official (→ replaced):
  grimblast, nordic-theme.
