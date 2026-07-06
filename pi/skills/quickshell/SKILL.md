---
name: quickshell
description: Quickshell QML bar config, component architecture, APIs, hardware integration, and debugging
---
# Quickshell Skill

## Scope
Use this skill for:
- Quickshell/QML bar configuration
- component architecture
- panels, popups, overlays, notifications, MPRIS, launchers
- Hyprland integration from Quickshell
- hardware/system controls exposed through Quickshell
- reload/log debugging

For detailed APIs, notification flow, MPRIS, hardware integration, and gotchas, read:
`/home/suraj/.pi/agent/skills/quickshell/REFERENCE.md`

## Key Paths
- Live config: `/home/suraj/.config/quickshell/`
- Main file: `/home/suraj/.config/quickshell/shell.qml`
- Theme file: `/home/suraj/.config/quickshell/theme/Theme.qml`
- Components: `/home/suraj/.config/quickshell/components/`
- Services: `/home/suraj/.config/quickshell/services/`
- Scripts: `/home/suraj/.config/quickshell/scripts/`

## Workflow
1. Identify the exact component/service/script involved.
2. Inspect relevant file before proposing changes.
3. Show proposed changes before writing.
4. After writing, reload:
   ```bash
   quickshell -r
   ```
5. Check logs:
   ```bash
   qs log
   ```
6. Stop and report any errors before continuing.

## Architecture Rules
- Keep state ownership clear; avoid duplicate sources of truth.
- Prefer explicit property threading over hidden globals.
- Use `shellRoot.propertyName` for root-level state.
- Avoid fragile `parent.parent` chains.
- Keep popup mutual exclusion centralized.
- Keep per-monitor state explicit.
- Do not hardcode theme values; use `Theme.qml`.
- Do not introduce polling unless necessary.
- Use optimistic UI only when the backend is slow and eventual consistency is acceptable.

## QML/Quickshell Rules
- No optional chaining.
- Avoid typed custom properties unless confirmed supported.
- Use `property var` for arrays/objects.
- Use `Connections` for signals from external objects.
- In delegates, prefer correct model role access for the delegate type.
- Verify Quickshell API names before using new APIs.
- Never invent imports; check existing files or reference docs first.

## Process Rules
- Use separate `Process` objects for separate commands.
- A running `Process` ignores new commands; guard or create another process.
- Parse JSON defensively.
- Background blocking commands when needed.

## Common Verification
```bash
quickshell -r
qs log
```

For systemd-managed sessions:
```bash
journalctl --user -u quickshell -n 30
```

## Dependencies
Common dependencies used by this config:
- `quickshell-git`
- `qt6-5compat`
- `matugen-bin`
- `ddcutil`
- `wl-clipboard`
- `grim`
- `slurp`
- `hyprpicker`
- `imagemagick`
- `python`
- `awww`

## Reference Configs
- Quickshell repo examples
- Existing files under `/home/suraj/.config/quickshell/`
- Detailed local reference: `/home/suraj/.pi/agent/skills/quickshell/REFERENCE.md`
