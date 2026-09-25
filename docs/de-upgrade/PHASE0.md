# Phase 0 — implementation and live-test gate

## Status

Repository work is implemented on `feat/de-shell` and **deployed with approval**;
no commit has been made. Phase 0 is **not signed off**: interactive desktop tests, Gaming Mode round-trip,
and the package-source decision remain open. Do not start Phase 1 yet.

## Baseline observed

- Starting revision: `362b9520f0b4767c6f1cb17016e77cd6dcc809d4` (`master`, clean).
- Hyprland 0.56.2, Lua config; `hyprctl configerrors` empty.
- Quickshell 0.3.1, package `0.3.1-1.1` from CachyOS; not `quickshell-git`.
- Official `extra/quickshell` is available in the local package database. No package
  transaction or database refresh was performed.
- Live Hyprland/Quickshell files matched the starting repository but are **separate
  copies**, not symlinks. Editing this branch does not deploy it.
- Observed options: animations=true, blur=true, inactive_opacity=0.8.
  These are observations, **not** restore defaults.
- Existing logs contain missing-icon and D-Bus warnings, plus the reproducible
  `NotificationToasts.qml:60: ReferenceError: root is not defined`.
- `/usr/bin/qmllint` and `qmlformat` are Qt 5. Use `/usr/lib/qt6/bin/*` for this shell.

## Implemented

- Imported supplied patches 1 and 2; kept the top-bar layout.
- Lua dispatch corrections, Caffeine/idle controls, night-light toggle and the
  Desktop Game Mode controls from patch 1.
- Converted the five Quickshell keybind calls and wallpaper accent IPC to
  `qs ipc call`, without changing keys or actions.
- Replaced the hard-coded Game Mode Bash helper with a Python stdlib helper that
  validates/saves pre-game settings, checks command effects, rolls back failed
  enable attempts, and preserves failed-restoration snapshots for retry.
- Game Mode chip and DND change only after a successful helper response. Concurrent
  toggles coalesce to the final desired state; failures are exposed in desktop IPC
  status and the System tile, with retry on the next five-second poll.
- Manual off without an active game returns to auto; forced off during a game lasts
  only until that game exits. Manual overrides are not persisted across shell restarts.
- Night-light state is periodically reconciled with wlsunset, including external
  starts/stops. hyprsunset migration remains Phase 2.
- Toast completion now runs in its surviving parent, not the delegate it destroys.
- Deferred unused launcher-action scaffolding until there is a Phase 5 caller.
- Corrected stale Phase 0 package instructions and unsafe cleanup/approval ordering
  in SPEC.md. No later-phase implementation or package-manifest changes.

## Recovery contract

State is stored under `$XDG_RUNTIME_DIR/quickshell-desktop-<session-hash>/gamemode.json`.
The hash derives from `HYPRLAND_INSTANCE_SIGNATURE`; a new compositor does not reuse
an old compositor's settings. A lock serializes helpers; an atomic snapshot is
published **before** applying changes and removed only after verified restoration.

On shell startup, the first valid gamemoded status reconciles that saved state:
continue Game Mode if a game is active, otherwise restore the snapshot. Corrupt state
is reported and retained, never evaluated as Lua or overwritten with defaults.
Pre-game DND is part of the snapshot, including when it was already enabled.

Recovery is not a watchdog: if Quickshell crashes, changes can remain until it is
restarted (or the helper is explicitly run). For approved manual recovery **inside
that same compositor**, run:

```sh
python3 ~/.config/quickshell/scripts/desktop-gamemode.py off false
```

The second argument matters only if no snapshot exists; a saved pre-game DND value
is returned in JSON. A running shell normally owns that DND state and should use its
controls instead. Do not delete a recovery snapshot before a successful restore.
Changes made to those three compositor settings during a game are superseded by
restoration of the pre-game snapshot. Do not enable idle suspend until Phase 2's
lock-before-sleep integration has passed its own tests.

## Repeatable offline checks

From the repository root:

```sh
python3 scripts/check-desktop-phase0.py
```

The check creates/deletes only its own scratch files inside the repository. It does
not invoke live hyprctl, start a desktop shell, install packages, or touch services.
It checks:

- Frozen Gaming Mode paths and Phase 0 keybind equivalence to the starting revision.
- No obsolete `qs msg` in active Hyprland/Quickshell code; whitespace checks.
- Lua/Bash/Python syntax and Qt 6 parsing of all 26 shell QML files.
- Actual Python helper logic with mocked hyprctl: non-default snapshots, both DND
  values, repeated on/off, restart recovery, partial failure, readback and corrupt state.
- Actual QML controller method bodies in Node: manual/auto transitions, in-flight
  toggles, acknowledgement and failure retry. This is a unit test, **not** a QML
  binding or Process-signal integration test.
- The real toast component under Qt Quick Test, offscreen with an isolated runtime
  directory and no session-bus access; two views share one model as on two monitors.

Results: all checks passed. The toast test was also run against the original source:
it failed with the same `root is not defined` error and a missing callback; the fix
passes (3 QtTest results, zero failures).

Qt 6 qmllint was inspected across all 26 shell QML files: **not clean** (689 warnings,
12 informational diagnostics, no error-severity diagnostics). These include existing
layout/unqualified-access warnings, Quickshell factory-type warnings (`PanelWindow`)
and missing `QProcess::ExitStatus` tooling metadata. There are also real pre-existing
property warnings, including HoverHandler.containsMouse in the unused SessionMenu
and a Repeater.barColor reference in SystemView. They are not all tooling noise.
Syntax passing or qmllint's exit status alone must not be presented as runtime validation.

## Deployment evidence — 2026-09-24

- User approved targeted backups, deployment and Quickshell restart.
- Backup: `~/.local/state/dotfiles-backups/phase0-20260924-204643/`.
  `manifest.json` records 11 pre-existing files and 3 newly introduced paths,
  before/deployed SHA-256 hashes, original instance and deployment stage.
- Rechecked live files against the starting revision: no drift. Offline checks passed.
- Stopped only instance `vr1r4vvlt` (PID 2299), then copied the 14 approved paths.
  Original launch was directly under Hyprland, not a systemd shell service.
- Started one live instance, `qcc1v9wvlt` (PID 62666), preserving the original process
  environment in memory. All 14 deployed files matched repository bytes and hashes.
- `Configuration Loaded`; no QML scene errors in the inspected startup log. Existing
  missing-icon warnings remain. This does not certify interactive paths not exercised.
- Desktop IPC reports caffeine=false, nightLight=true, gameMode=false, override=auto,
  gamemoded=false, known=true, desired=false, idle=Active, error empty.
- `hyprctl configerrors` remains empty. All 50 shortcut keys/flags are unchanged.
  Lua callback IDs and iteration order changed on reload; compare the key/flag set
  separately from source, which differs only by the five IPC spelling replacements.
- Animations=true, blur=true and inactive_opacity=0.8 remain unchanged after startup.
- No package/service changes, logout, suspend or Gaming Mode transitions were
  performed. No frozen gaming-session files were changed.

## Live test results

Approved reversible tests; state restored after each run.

- Caffeine: toggles, idle status reports paused, restored. Timed inhibition not tested.
- Night Light: stops/starts wlsunset; external state reconciled.
- Desktop Game Mode, manual: animations/blur off, inactive opacity 1.0, snapshot saved;
  off restores exact values and clears snapshot; override returns to auto.
- Rapid toggles (4x): settle to off with original settings.
- Automatic (`gamemoderun sleep`): detected in ~1.5 s; restored on exit. CPU governors
  were already `performance` on all 32 policies, so Feral GameMode changed nothing there.
- Restart recovery: shell killed mid-game -> relaunch continued Game Mode, restored on
  game exit. Shell killed with manual Game Mode on and no game -> startup restored.
- **Bug found and fixed:** the Night Light toggle started wlsunset as a Quickshell
  child, so a shell restart killed it. Now launched detached (parent is systemd);
  verified the same wlsunset PID survives a restart. Redeployed that one file; the
  backup manifest hash was updated.
- No QML runtime errors in any new instance.

**Logout passed** on 2026-09-25 (twice, via the session menu; SDDM login afterwards).

**Deferred by Suraj:** timed idle lock/screens-off/wake and Caffeine inhibition,
and the Gamescope Gaming Mode round-trip. Phase 0 is functionally complete
for everything else but not formally signed off until those pass.

## Supervised deployment and smoke-test checklist

Steps 1–3 are complete for the deployment above; steps 4–10 remain pending.

**Ask before live-file changes or shell restart.** Do not run the repository's full
shell beside the existing shell: both would manage idle/notifications and session IPC.

1. Recheck repository/live-file drift; inventory the selected running shell and its
   launch mechanism with `qs list`. Save targeted copies of every live file to change
   and record which new paths did not exist. No broad bootstrap or directory sync.
2. With approval, deploy only Phase 0's changed Hyprland/Quickshell/wlogout files.
   Account for `settings.watchFiles: true`: stop the selected instance before copying
   a multi-file update, then launch exactly one instance using its prior mechanism.
3. Check fresh logs for QML errors and compare known baseline warnings. Check
   `hyprctl configerrors`, then `qs ipc call desktop status`.
4. On both monitors: existing and empty workspace clicks; overview window clicks and
   keys 1–5; launcher/screenshot/wallpaper keys; mixer floating placement; Wi-Fi action.
5. Caffeine chip/tile on/off; wait past lock timeout with Caffeine on and off; verify
   video inhibition, lock, DPMS off and wake. Never use forced-idle as proof of an
   inhibitor: Hyprland's force_idle bypasses inhibitors.
6. Night-light on/off, including an externally stopped process.
7. A bounded gamemoderun process: chip/DND/blur changes after polling; verify exact
   restoration of animations/blur/opacity and pre-enabled/pre-disabled DND. Test
   manual on/off before the next game and rapid repeated clicks.
8. Approved shell restart with a game active, then game exit; also restart with a
   saved snapshot after the game has already ended. Check status/logged failures.
9. Test Logout only when ready to end the session. Sleep and Gaming Mode transitions
   are separate supervised actions, not automated checks. Complete §7.3's Gaming
   Mode round-trip before Phase 0 sign-off.
10. Decide whether to replace the existing CachyOS Quickshell build with the official
    Arch build. Ask before the transaction and repeat the smoke test if it changes.

Rollback: stop the selected new shell, restore Game Mode settings from its snapshot
if active, restore only the backed-up live files, remove only the recorded newly
introduced live paths with approval, and restart using the original launch mechanism.
Do not use git reset, broad deletion, or alter the frozen gaming-session helpers.
