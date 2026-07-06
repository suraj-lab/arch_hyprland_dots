# Gaming Mode / Deck Mode restore notes

This dotfiles repo stores the reinstall-facing subset of the validated Gaming Mode setup:

- `packages/gaming-mode.txt` — required gaming/session packages
- `.config/environment.d/99-gaming-session.conf` — RX 9070 XT + DP-2 session env
- `.config/gamescope/scripts/dell.aw3423dwf.lua` — AW3423DWF refresh profile
- `.config/hypr/modules/binds.lua` — `Super+Shift+S` enters Gaming Mode
- `.config/hypr/modules/autostart.lua` — return cleanup hook
- `deploy/gaming/` — vendored root/session helpers plus the searchable `Gaming Mode` app launcher from the validated private project
- `scripts/install-gaming-mode.sh` — Gaming Mode-only wrapper around `scripts/bootstrap-arch.sh`

Install/refresh only Gaming Mode from this repo:

```bash
./scripts/install-gaming-mode.sh --yes
```

The private `arch-gaming-optimization` repo remains the research/audit source of truth, but the reinstall-critical root-level deployment is now vendored here so a fresh machine does not need that private clone to boot into Gaming Mode.

Known-good validation, 2026-07-04:

- Full Gaming Mode: SteamOS-style session switch via `gamescope-session-cachyos`
- Backend: `gamescope-session-cachyos`
- Display: AW3423DWF on RX 9070 XT `DP-2`, 3440x1440@165
- Aux monitor: ViewSonic `HDMI-A-1`, forced off at DRM level while in Gaming Mode
- Works: HDR, VRR, Steam suspend/resume, clean desktop return, Quickshell relaunch
- Full Gaming Mode entry preflights desktop Steam first so updates/validation happen visibly before the gamescope session starts

Do not replace full Gaming Mode with `gamescope-session-git` / `gamescope-session-steam-git` unless troubleshooting again; the CachyOS backend is the validated maintenance-friendly path.
