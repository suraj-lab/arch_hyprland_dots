#!/usr/bin/env python3
"""lock.sh with a fake hyprlock: a crash restarts it, an unlock ends it, a broken hyprlock
gives up, and only one guard runs. Never starts the real hyprlock."""
import fcntl
import os
from pathlib import Path
import subprocess
import tempfile
import time

SCRIPT = Path(__file__).resolve().parents[2] / ".config/quickshell/scripts/lock.sh"

with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    bin_dir = tmp / "bin"
    bin_dir.mkdir()
    # hyprlock exits with the next code in $HOME/codes (one per run), logging each run.
    stubs = {"hyprlock": 'echo run >> "$HOME/runs"; c=$(head -1 "$HOME/codes"); sed -i 1d "$HOME/codes"; exit "${c:-0}"',
             "systemd-cat": 'shift 2; exec "$@"',            # systemd-cat -t hyprlock hyprlock
             "logger": 'echo "$*" >> "$HOME/logged"',
             "pidof": '[ -f "$HOME/running" ]'}
    for name, body in stubs.items():
        (bin_dir / name).write_text("#!/bin/sh\n" + body + "\n")
        (bin_dir / name).chmod(0o700)
    env = dict(os.environ, HOME=str(tmp), XDG_RUNTIME_DIR=str(tmp), PATH=f"{bin_dir}:/usr/bin")

    def guard(codes, fast="10"):
        for name in ("runs", "logged"):
            (tmp / name).unlink(missing_ok=True)
        (tmp / "codes").write_text("".join(f"{c}\n" for c in codes))
        rc = subprocess.run(["bash", str(SCRIPT)], env=dict(env, HYPRLOCK_FAST_SEC=fast), timeout=30).returncode
        runs = len((tmp / "runs").read_text().split()) if (tmp / "runs").exists() else 0
        logged = (tmp / "logged").read_text() if (tmp / "logged").exists() else ""
        return rc, runs, logged

    assert guard([0]) == (0, 1, "")                                  # unlocked: one run
    started = time.monotonic()
    rc, runs, logged = guard([139, 134, 0], fast="0")                 # crashes after a long run
    assert time.monotonic() - started < 1, "a crash after a long run must restart at once"
    assert (rc, runs) == (0, 3) and logged.count("exited with") == 2, (rc, runs, logged)
    assert "exited with 139" in logged
    rc, runs, _ = guard([1] * 9)                                      # broken at startup
    assert (rc, runs) == (1, 5), (rc, runs)
    (tmp / "running").touch()                                         # locked by the bind already
    assert guard([0])[:2] == (0, 0)
    (tmp / "running").unlink()
    with open(tmp / "hyprlock-guard.lock", "w") as held:              # another guard holds the lock
        fcntl.flock(held, fcntl.LOCK_EX)
        assert guard([0])[:2] == (0, 0)
print("PASS: lock guard restarts a crashed hyprlock, ends on unlock, gives up on a broken one, runs once")
