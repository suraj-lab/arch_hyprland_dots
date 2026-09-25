#!/usr/bin/env python3
"""Offline Phase 3 checks; never connect to the running desktop or user bus."""
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix=".p3-", dir=ROOT) as tmp:
    home = Path(tmp)
    config = home / ".config/quickshell/settings.json"
    config.parent.mkdir(parents=True)
    shutil.copytree(ROOT / ".config/quickshell/services", config.parent / "services")
    fixture = config.parent / "shell.qml"
    fixture.write_text((ROOT / "scripts/tests/shell-config.qml").read_text().replace(
        '"../../.config/quickshell/services"', '"services"'))
    (home / "r").mkdir(mode=0o700)
    # Desktop starts these on construction. No real controller/service commands may run.
    (home / "bin").mkdir()
    for name, body in {
        "gamemoded": "printf 'gamemode is inactive\\n'",
        "pgrep": "exit 1",
        "pkill": "exit 1",
        "hyprctl": "exit 1",
        "systemctl": "exit 1",
        "hyprlock": "exit 1",
    }.items():
        command = home / "bin" / name
        command.write_text("#!/bin/sh\n" + body + "\n")
        command.chmod(0o700)
    (config.parent / "scripts").mkdir()
    (config.parent / "scripts/desktop-gamemode.py").write_text(
        'print(\'{"gameMode":false,"dnd":false}\')\n')
    env = dict(os.environ, HOME=tmp, PATH=str(home / "bin") + ":/usr/bin",
               XDG_CONFIG_HOME=str(home / ".config"),
               XDG_CACHE_HOME=str(home / ".cache"), XDG_STATE_HOME=str(home / ".state"),
               XDG_DATA_HOME=str(home / ".local/share"), XDG_RUNTIME_DIR=str(home / "r"),
               DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent",
               DBUS_SYSTEM_BUS_ADDRESS="unix:path=/nonexistent", GSETTINGS_BACKEND="memory",
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               QML_DISABLE_DISK_CACHE="1", QT_LOGGING_RULES="qml.debug=true;*.warning=true;*.critical=true")
    for key in ("HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY"):
        env.pop(key, None)
    for test in ("test_desktop_controller.js", "test_shell_services.js"):
        subprocess.run(["node", "scripts/tests/" + test],
                       cwd=ROOT, env=env, check=True, timeout=30)

    lines = queue.Queue()
    log = []
    proc = subprocess.Popen(["quickshell", "--no-color", "--path", str(fixture)],
                            cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True)

    def collect():
        for line in proc.stdout:
            log.append(line)
            lines.put(line)

    reader = threading.Thread(target=collect, daemon=True)
    reader.start()

    def expect(lock=600, dpms=900, suspend=0):
        expected = dict(lockSec=lock, dpmsSec=dpms, suspendSec=suspend)
        deadline = time.monotonic() + 5
        config_seen = desktop_seen = False
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=0.1)
            except queue.Empty:
                continue
            if "CONFIG " in line and json.loads(line.split("CONFIG ", 1)[1]) == expected:
                config_seen = True
            if "DESKTOP " in line:
                desktop = json.loads(line.split("DESKTOP ", 1)[1])
                desktop_seen = desktop == dict(expected, dnd=False, backendDnd=False, gameMode=False)
            if config_seen and desktop_seen:
                return
        raise AssertionError(f"No config update to {expected}\n{''.join(log)}")

    try:
        expect()  # missing file: defaults, and watching for its creation
        config.write_text('{"idle":{"lockSec":1200,"dpmsSec":1500,"suspendSec":1800}}')
        expect(1200, 1500, 1800)
        config.write_text('{"idle":{"lockSec":0}}')
        expect(0)
        config.write_text('{"idle":{"lockSec":-1,"dpmsSec":"20","suspendSec":1.5}}')
        expect()
        config.write_text('{"idle":{"lockSec":700}}')
        expect(700)
        config.write_text('{"idle":')  # an incomplete editor save must retain good settings
        time.sleep(0.3)
        updates = []
        while not lines.empty():
            line = lines.get_nowait()
            if "CONFIG " in line:
                updates.append(json.loads(line.split("CONFIG ", 1)[1]))
        assert all(v["lockSec"] == 700 for v in updates), updates
        replacement = config.with_suffix(".tmp")
        replacement.write_text('{}')
        replacement.replace(config)  # atomic editor saves must also reload
        expect()
        config.write_text('{"idle":{"lockSec":true,"dpmsSec":2147483648}}')
        expect()
        bad = [line for line in log if any(marker in line for marker in (
            " ERROR", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration"))]
        assert not bad, "".join(bad)
        print("PASS: Config defaults, file creation, watched/atomic edits, zero, partial/invalid settings")
        print("PASS: Desktop singleton startup, live timeout bindings and two-way DND wiring (stubbed commands)")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        reader.join(timeout=1)
        proc.stdout.close()
