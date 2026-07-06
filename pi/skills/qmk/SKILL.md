---
name: qmk
description: QMK firmware workflow for ZSA Moonlander compile, flash, update, and debugging
---

# QMK Skill

## Scope
Use this skill for ZSA Moonlander QMK maintenance:
- compiling firmware
- flashing firmware
- updating QMK upstream
- diagnosing build or flash failures
- editing the active keymap

For detailed keycodes, layers, macros, config, RGB, debounce, Moonlander specifics, and gotchas, see:
`/home/suraj/.pi/agent/skills/qmk/REFERENCE.md`

## Key Paths
- QMK firmware root: `/home/suraj/qmk_firmware/`
- Active keymap: `/home/suraj/qmk_firmware/keyboards/zsa/moonlander/keymaps/new/`
- Keymap file: `/home/suraj/qmk_firmware/keyboards/zsa/moonlander/keymaps/new/keymap.c`
- Config file: `/home/suraj/qmk_firmware/keyboards/zsa/moonlander/keymaps/new/config.h`
- Rules file: `/home/suraj/qmk_firmware/keyboards/zsa/moonlander/keymaps/new/rules.mk`
- Project memory: `/home/suraj/qmk_firmware/keyboards/zsa/moonlander/keymaps/new/MEMORY.md`

## Core Commands
Run from `/home/suraj/qmk_firmware/`.

Compile:
```bash
qmk compile -kb zsa/moonlander -km new
```

Flash:
```bash
qmk flash -kb zsa/moonlander -km new
```

Clean rebuild:
```bash
qmk clean
qmk compile -kb zsa/moonlander -km new
```

Environment check:
```bash
qmk doctor
```

## Workflow
1. Inspect the requested change.
2. Identify the exact file to edit.
3. Show proposed changes before writing.
4. Compile after edits:
   ```bash
   qmk compile -kb zsa/moonlander -km new
   ```
5. If compile passes, ask before flashing.
6. Flash only after explicit confirmation:
   ```bash
   qmk flash -kb zsa/moonlander -km new
   ```
7. If flashing fails, stop and report the exact error.

## Update Workflow
When updating QMK upstream:

```bash
cd /home/suraj/qmk_firmware
git status --short
git remote -v
git fetch upstream
git pull upstream master
qmk clean
qmk compile -kb zsa/moonlander -km new
```

Rules:
- Check `git status` before pulling.
- Do not overwrite local keymap changes without confirmation.
- If merge conflicts occur, stop and explain the conflicted files.
- After update, compile before flashing.
- Ask before flashing.

## Safety Rules
- Never flash without explicit confirmation.
- Never discard local QMK changes unless explicitly requested.
- Never resolve merge conflicts by guessing.
- If a compile error occurs, diagnose the first meaningful error before editing.
- If flash fails, do not repeatedly retry blindly.
- Keep changes focused and reversible.

## Failure Handling
Compile failure:
```text
- capture the first meaningful compiler error
- identify likely source file and line
- explain root cause
- propose a minimal fix
```

Flash failure:
```text
- confirm keyboard bootloader/DFU state
- report the exact flash error
- do not retry more than once without new information
```

Rollback reminder:
```bash
git log --oneline -5
git checkout <known-good-commit> -- keyboards/zsa/moonlander/keymaps/new/
qmk compile -kb zsa/moonlander -km new
```
