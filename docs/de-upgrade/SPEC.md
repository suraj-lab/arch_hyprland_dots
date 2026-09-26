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
| `dashboard` | 920×420 | click clock or media in the bar, `Super+D`, `qs ipc call pill open dashboard` | Dashboard / Media / Performance / Weather tabs |
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
hints from toplevels) · active window title (elided) · spacer · now-playing (MPRIS) ·
spacer · CPU% · RAM% · tray (`SystemTray`) · network/Bluetooth/volume icons · Caffeine
and Game Mode chips (only when active) · update badge (Phase 6) · clock · power.
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
| `Super+D` | dashboard surface | `hl.dsp.exec_cmd("qs ipc call pill open dashboard")` |
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
