#!/usr/bin/env python3
"""Offline checks: exercise the real snapshot/Lua code with a fake hyprctl."""
import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "gamemode", ROOT / ".config/quickshell/scripts/desktop-gamemode.py")
gm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gm)

state = {"animations": False, "blur": True, "opacity": 0.63}
fail_next = False
reject_next = False
calls = []


def fake_hyprctl(*args):
    global fail_next, reject_next
    calls.append(args)
    if args[:2] == ("-j", "getoption"):
        key, field = {"animations:enabled": ("animations", "bool"),
                      "decoration:blur:enabled": ("blur", "bool"),
                      "decoration:inactive_opacity": ("opacity", "float")}[args[2]]
        return json.dumps({field: state[key]})
    assert args[0] == "eval", args
    if fail_next:
        fail_next = False
        state["blur"] = False  # simulate a partial apply, not just a clean failure
        raise RuntimeError("simulated failure")
    if reject_next:
        reject_next = False
        return "config error"  # successful CLI exit with no actual change
    booleans = re.findall(r"enabled = (true|false)", args[1])
    assert len(booleans) == 2, args
    state.update(animations=booleans[0] == "true", blur=booleans[1] == "true",
                 opacity=float(re.search(r"inactive_opacity = ([\d.]+)", args[1])[1]))
    return "ok"


def fails(action):
    try:
        action()
    except (ValueError, RuntimeError):
        return
    raise AssertionError("expected failure")


gm.hyprctl = fake_hyprctl  # no command in this test can reach the compositor
with tempfile.TemporaryDirectory(prefix="gamemode-", dir=Path(__file__).parent) as tmp:
    path = Path(tmp) / "state.json"
    original = state.copy()
    for original_dnd in (False, True):
        assert gm.transition(path, False, original_dnd) == {"gameMode": False, "dnd": original_dnd}
        assert gm.transition(path, True, original_dnd) == {"gameMode": True, "dnd": True}
        saved = path.read_text()
        assert state == gm.GAME
        # New helper process / shell restart: never snapshot already-modified values.
        assert gm.transition(path, True, True)["gameMode"]
        assert path.read_text() == saved
        assert gm.transition(path, False, True) == {"gameMode": False, "dnd": original_dnd}
        assert state == original and not path.exists()
        assert not gm.transition(path, False, original_dnd)["gameMode"]

    # Failed enable rolls back and leaves enough state for restart recovery.
    fail_next = True
    fails(lambda: gm.transition(path, True, False))
    assert path.exists() and state == original
    assert gm.transition(path, False, True)["dnd"] is False

    gm.transition(path, True, False)
    saved = path.read_text()
    fail_next = True
    fails(lambda: gm.transition(path, False, True))
    assert path.read_text() == saved
    gm.transition(path, False, True)
    assert state == original and not path.exists()

    reject_next = True
    fails(lambda: gm.transition(path, True, False))
    assert state == original and path.exists()
    gm.transition(path, False, True)

    # Corrupt recovery data must not execute Lua or replace the saved file.
    for data in ["not json", json.dumps({**original, "dnd": "false"}),
                 json.dumps({**original, "opacity": "1); os.execute('bad')", "dnd": False}),
                 json.dumps({**original, "opacity": float("nan"), "dnd": False})]:
        path.write_text(data)
        count = len(calls)
        fails(lambda: gm.transition(path, True, False))
        assert len(calls) == count and path.read_text() == data

print("PASS: snapshots, DND, repeated on/off, restart recovery, partial failure, readback, corrupt state")
