# Gaming Mode / Deck Mode restore notes

This dotfiles repo stores the reinstall-facing subset of the validated Gaming Mode setup:

- `packages/gaming-mode.txt` — required gaming/session packages
- `.config/environment.d/99-gaming-session.conf` — RX 9070 XT + DP-2 session env
- `.config/gamescope/scripts/dell.aw3423dwf.lua` — AW3423DWF refresh profile
- `.config/hypr/modules/binds.lua` — `Super+Shift+S` enters Gaming Mode
- `.config/hypr/modules/autostart.lua` — return cleanup hook
- `scripts/install-gaming-mode.sh` — package/home-config bootstrap

The full root-level deployment lives in the private repo:

```bash
git clone git@github.com:suraj-lab/arch-gaming-optimization.git ~/Projects/arch-gaming-optimization
cd ~/Projects/arch-gaming-optimization
sudo ./scripts/apply-phase34.sh
./scripts/verify-deck-mode.sh
```

Known-good validation, 2026-07-04:

- Backend: `gamescope-session-cachyos`
- Display: AW3423DWF on RX 9070 XT `DP-2`, 3440x1440@165
- Aux monitor: ViewSonic `HDMI-A-1`, forced off at DRM level while in Gaming Mode
- Works: HDR, VRR, Steam suspend/resume, clean desktop return, Quickshell relaunch

Do not replace this with `gamescope-session-git` / `gamescope-session-steam-git` unless troubleshooting again; the CachyOS backend is the validated maintenance-friendly path.
