#!/usr/bin/env python3
"""Desktop-only Game Mode. Save before changing; restore even after a shell restart.

Usage: desktop-gamemode.py on|off true|false  (second argument: current DND)
No system/gaming-session settings are changed. State belongs to one compositor.
"""

import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys


GAME = {"animations": False, "blur": False, "opacity": 1.0}


def validate(options):
    if (not isinstance(options, dict)
            or type(options.get("animations")) is not bool
            or type(options.get("blur")) is not bool
            or type(options.get("opacity")) not in (int, float)
            or not math.isfinite(options["opacity"])
            or not 0 <= options["opacity"] <= 1):
        raise ValueError("invalid compositor snapshot; refusing to overwrite it")
    return options


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], check=True, capture_output=True,
                          text=True, timeout=5).stdout


def read_options():
    options = {}
    for name, key, field in [("animations", "animations:enabled", "bool"),
                             ("blur", "decoration:blur:enabled", "bool"),
                             ("opacity", "decoration:inactive_opacity", "float")]:
        options[name] = json.loads(hyprctl("-j", "getoption", key))[field]
    return validate(options)


def apply_options(options):
    validate(options)
    hyprctl("eval", "hl.config({ animations = { enabled = %s }, decoration = { "
            "blur = { enabled = %s }, inactive_opacity = %s } })" % (
                json.dumps(options["animations"]), json.dumps(options["blur"]),
                json.dumps(options["opacity"])))
    # hyprctl can return success with an error in its response. Verify the effect.
    actual = read_options()
    if (actual["animations"] != options["animations"]
            or actual["blur"] != options["blur"]
            or not math.isclose(actual["opacity"], options["opacity"], abs_tol=1e-6)):
        raise RuntimeError("Hyprland did not apply the requested settings")


def transition(path, enabled, dnd):
    """Caller holds the session lock. Never replace an existing recovery snapshot."""
    snapshot = None
    if path.exists():
        snapshot = json.loads(path.read_text())
        validate(snapshot)
        if type(snapshot.get("dnd")) is not bool:
            raise ValueError("invalid DND snapshot")
    if enabled:
        if snapshot is None:
            snapshot = dict(read_options(), dnd=dnd)
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps(snapshot))
            temporary.replace(path)  # publish before changing compositor state
        try:
            apply_options(GAME)
        except Exception:
            # Retain the snapshot even if rollback fails; a later off can retry.
            apply_options(snapshot)
            raise
        return {"gameMode": True, "dnd": True}
    if snapshot is not None:
        apply_options(snapshot)
        path.unlink()  # remove only after a verified restore
        dnd = snapshot["dnd"]
    return {"gameMode": False, "dnd": dnd}


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("on", "off") or sys.argv[2] not in ("true", "false"):
        raise ValueError("usage: desktop-gamemode.py on|off true|false")
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    signature = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    if not runtime.is_absolute() or not signature:
        raise ValueError("a live Hyprland session and absolute XDG_RUNTIME_DIR are required")
    session = hashlib.sha256(signature.encode()).hexdigest()[:24]
    directory = runtime / ("quickshell-desktop-" + session)
    directory.mkdir(mode=0o700, exist_ok=True)
    with (directory / "gamemode.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        result = transition(directory / "gamemode.json", sys.argv[1] == "on", sys.argv[2] == "true")
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"desktop-gamemode: {error}", file=sys.stderr)
        sys.exit(1)
