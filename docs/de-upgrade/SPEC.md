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
- Approved live deployment/startup/IPC checks passed on 2026-09-24. Interactive,
  idle and Gaming Mode round-trip checks remain pending; see PHASE0.md.

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
| `hover` | min(1200, clamp)×46 | pointer in the bottom 4 px strip for ≥150 ms (dwell), or `Super+grave` | full bar row (§3.4) |
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
`Super+grave` toggles `peek` on the focused monitor. Peeking maps the pill in its
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
| `Super+grave` | peek / expand pill | `hl.dsp.exec_cmd("qs ipc call pill peek")` |
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
    "brightness": { "buses": { "DP-2": 8, "HDMI-A-1": 10 } },
    "appearance": { "animations": true },
    "monitors": { "HDMI-A-1": { "pill": { "hoverExpand": false } } }
  }
  ```
  (Confirm the DP-2 = bus 8 mapping on the machine; the current code writes to both
  buses 8 and 10.)
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
- Fullscreen hide and `Super+grave` peek (§3.3). IPC target `pill`: `peek()`,
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
1. Pill rest style: **tab** / handle.
2. Expand trigger: **bottom-edge hover with 150 ms dwell + `Super+grave`** / Super tap
   (release bind) / click only.
3. HDMI-A-1 pill: same as main / **rest-only, click to expand**.
4. Lock-before-sleep: **small logind listener service** / hypridle for sleep hooks only.
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
