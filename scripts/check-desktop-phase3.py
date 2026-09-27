#!/usr/bin/env python3
"""Offline Phase 3 checks; never connect to the running desktop, user bus or network."""
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

hourly = [{"weatherCode": "113"}] * 8
WEATHER = {"current_condition": [{"temp_C": "12", "FeelsLikeC": "10", "humidity": "80",
                                  "windspeedKmph": "15", "weatherCode": "116",
                                  "weatherDesc": [{"value": "Partly cloudy"}]}],
           "weather": [{"date": "2026-09-2%d" % i, "maxtempC": "20", "mintempC": "9",
                        "hourly": hourly} for i in range(3)]}

with tempfile.TemporaryDirectory(prefix=".p3-", dir=ROOT) as tmp:
    home = Path(tmp)
    config = home / ".config/quickshell/settings.json"
    config.parent.mkdir(parents=True)
    shutil.copytree(ROOT / ".config/quickshell/services", config.parent / "services")
    fixture = config.parent / "shell.qml"
    fixture.write_text((ROOT / "scripts/tests/shell-config.qml").read_text().replace(
        '"../../.config/quickshell/services"', '"services"'))
    (home / "r").mkdir(mode=0o700)
    (home / "weather.json").write_text(json.dumps(WEATHER))
    # Services start these on construction. No real controller/service/network command may run.
    (home / "bin").mkdir()
    for name, body in {
        "gamemoded": "printf 'gamemode is inactive\\n'",
        "pgrep": "exit 1",
        "pkill": "exit 1",
        "hyprctl": "exit 1",
        "systemctl": "exit 1",
        "hyprlock": "exit 1",
        "pactl": "printf '62\\tdock\\tPipeWire\\ts24le 2ch 48000Hz\\tRUNNING\\n'",
        "curl": 'printf "%s\\n" "$*" >> "$HOME/curl-args"; cat "$HOME/weather.json"',
    }.items():
        command = home / "bin" / name
        command.write_text("#!/bin/sh\n" + body + "\n")
        command.chmod(0o700)
    (home / "bin" / "ddcutil").write_text('''#!/usr/bin/python3
import json, os, sys, time
from pathlib import Path
home = Path(os.environ["HOME"])
args = sys.argv[1:]
with (home / "ddc-calls").open("a") as log:
    log.write(json.dumps(args) + "\\n")
if args[0] == "detect":
    print("Display 1\\n I2C bus: /dev/i2c-8\\n DRM connector: card1-HDMI-A-1")
    print("Display 2\\n I2C bus: /dev/i2c-10\\n DRM connector: card1-DP-2")
else:
    bus = args[args.index("--bus") + 1]
    state = home / ("ddc-value-" + bus)
    if args[0] == "getvcp":
        if bus == "77":
            sys.exit(2)
        if bus == "78":
            print("VCP 10 ERR")
            sys.exit(0)
        print("VCP 10 C", state.read_text() if state.exists() else "28", "100")
    elif args[0] == "setvcp":
        time.sleep(0.1)  # keep Process busy while the fixture drags again
        if bus == "10" and args[2] == "60":
            sys.exit(3)  # one monitor fails; the combined write must report failure
        state.write_text(args[2])
''')
    (home / "bin" / "ddcutil").chmod(0o700)
    (config.parent / "scripts").mkdir()
    (config.parent / "scripts/desktop-gamemode.py").write_text(
        'print(\'{"gameMode":false,"dnd":false}\')\n')
    env = dict(os.environ, LC_ALL="C.UTF-8", HOME=tmp, PATH=str(home / "bin") + ":/usr/bin",
               XDG_CONFIG_HOME=str(home / ".config"),
               XDG_CACHE_HOME=str(home / ".cache"), XDG_STATE_HOME=str(home / ".state"),
               XDG_DATA_HOME=str(home / ".local/share"), XDG_RUNTIME_DIR=str(home / "r"),
               DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent",
               DBUS_SYSTEM_BUS_ADDRESS="unix:path=/nonexistent", GSETTINGS_BACKEND="memory",
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               QML_DISABLE_DISK_CACHE="1", QT_LOGGING_RULES="qml.debug=true;*.warning=true;*.critical=true")
    for key in ("HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY",
                "PIPEWIRE_REMOTE", "PIPEWIRE_RUNTIME_DIR", "PULSE_SERVER"):
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

    def wait_for(tag, accept, what, timeout=5, since=0):
        # Scan the whole log: expect() may already have taken the line off the queue.
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for line in list(log)[since:]:
                if tag + " " in line:
                    value = json.loads(line.split(tag + " ", 1)[1])
                    if accept(value):
                        return value
            time.sleep(0.1)
        raise AssertionError(f"No {tag} line with {what}\n{''.join(log)}")

    def expect(lock=600, dpms=900, suspend=0, location="London", caffeine=False):
        idle = dict(lockSec=lock, dpmsSec=dpms, suspendSec=suspend)
        desktop = dict(idle, dnd=False, backendDnd=False, gameMode=False)
        seen = set()
        deadline = time.monotonic() + 5
        while seen != {"CONFIG", "DESKTOP"}:
            if time.monotonic() > deadline:
                raise AssertionError(f"No update to {idle}, {location}\n{''.join(log)}")
            try:
                line = lines.get(timeout=0.1)
            except queue.Empty:
                continue
            if "CONFIG " in line:
                c = json.loads(line.split("CONFIG ", 1)[1])
                if c == dict(idle=dict(idle, caffeine=caffeine), weather=dict(location=location)):
                    seen.add("CONFIG")
            if "DESKTOP " in line and json.loads(line.split("DESKTOP ", 1)[1]) == desktop:
                seen.add("DESKTOP")

    try:
        expect()  # missing file: defaults, and watching for its creation
        notifs = wait_for("NOTIFS", lambda v: True, "a notification test result")
        assert notifs == {
            "toasts": 4, "history": 5, "unread": 5, "oldestToast": 2, "body": "x & y",
            "criticalTimeout": 0, "customTimeout": 9000, "deskDnd": True,
            "dnd": [8, 7, 7],                    # history grows; no badge or toast under DND
            "dismissed": [True, 7, 3],
            "media": [-1, "Spotify", "Song", "Artist", 3000, 7],  # toast only, not history
            "cleared": [0, 0, 8, False],
        }, notifs
        wait_for("WEATHER", lambda v: v == dict(location="London", temp="12", desc="Partly cloudy",
                                                days=3, error=False), "the London forecast")
        wait_for("AUDIO", lambda v: v == dict(ready=False, volume=0, sinks=0, apps=0,
                                              states={"dock": "running"}),
                 "Audio loaded without PipeWire, pactl states parsed")
        wait_for("NETBT", lambda v: v == dict(wifi=False, ssid="", networks=0, bt=False),
                 "Net/Bt loaded without D-Bus")
        wait_for("BRIGHT", lambda v: v["ready"] and abs(v["brightness"] - 0.28) < 0.001
                 and v["buses"] == 2, "Brightness detect -> read with stubbed ddcutil")
        wait_for("BRIGHT_WRITE", lambda v: v == 0.9, "rapid drag ends at 90%")
        wait_for("BRIGHT_FAILURE", lambda v: v["value"] == 0.6 and "write failed (3)" in v["error"],
                 "partial write failure remains visible after readback")
        wait_for("BRIGHT_RECOVER", lambda v: v == dict(value=0.5, error=""), "successful retry")
        calls = [json.loads(line) for line in (home / "ddc-calls").read_text().splitlines()]
        writes = [(args[2], args[args.index("--bus") + 1]) for args in calls if args[0] == "setvcp"]
        assert writes == [(str(value), str(bus)) for value in (40, 90, 60, 50) for bus in (8, 10)], writes
        assert sum(args[0] == "detect" for args in calls) == 1, calls
        sysmon = wait_for("SYSMON", lambda v: True, "CPU/memory/temperature readings", timeout=8)
        assert 0 <= sysmon["cpu"] <= 100 and 0 < sysmon["mem"] <= 100, sysmon
        assert 0 < sysmon["temp"] < 120 and sysmon["path"].startswith("/sys/"), sysmon

        config.write_text('{"idle":{"lockSec":1200,"dpmsSec":1500,"suspendSec":1800}}')
        expect(1200, 1500, 1800)
        config.write_text('{"idle":{"lockSec":0}}')
        expect(0)
        config.write_text('{"idle":{"lockSec":0,"caffeine":true}}')   # remembered Caffeine (6.5a)
        expect(0, caffeine=True)
        config.write_text('{"idle":{"lockSec":-1,"dpmsSec":"20","suspendSec":1.5}}')
        expect()
        config.write_text('{"idle":{"lockSec":700},"weather":{"location":"  New York "}}')
        expect(700, location="New York")
        wait_for("WEATHER", lambda v: v["location"] == "New York", "a New York refetch")
        config.write_text('{"idle":')  # an incomplete editor save must retain good settings
        time.sleep(0.3)
        updates = []
        while not lines.empty():
            line = lines.get_nowait()
            if "CONFIG " in line:
                updates.append(json.loads(line.split("CONFIG ", 1)[1]))
        assert all(v["idle"]["lockSec"] == 700 for v in updates), updates
        replacement = config.with_suffix(".tmp")
        replacement.write_text('{}')
        replacement.replace(config)  # atomic editor saves must also reload; sections reset
        expect()
        config.write_text('{"idle":{"lockSec":true,"dpmsSec":2147483648,"caffeine":1},"weather":{"location":42}}')
        expect()
        config.write_text('{"weather":{"location":"' + "x" * 101 + '"}}')
        expect()
        config.write_text('{"brightness":{"buses":{"DP-2":20,"DP-3":"bad"}}}')
        wait_for("BUS_OVERRIDES", lambda v: v == {"DP-2": 20}, "validated brightness override")
        wait_for("BRIGHT_MAP", lambda v: v == {"HDMI-A-1": 8, "DP-2": 20}, "override merged with detection")
        since = len(log)
        config.write_text('{}')
        wait_for("BUS_OVERRIDES", lambda v: v == {}, "removed override resets to auto", since=since)
        wait_for("BRIGHT_MAP", lambda v: v == {"HDMI-A-1": 8, "DP-2": 10}, "detected buses restored", since=since)
        config.write_text('{"brightness":{"buses":{"HDMI-A-1":77}}}')
        wait_for("BRIGHT_ERROR", lambda v: v == "Brightness read failed (2)", "read failure is not hidden by a pipe")
        config.write_text('{"brightness":{"buses":{"HDMI-A-1":78}}}')
        wait_for("BRIGHT_ERROR", lambda v: v == "Invalid DDC brightness reading", "malformed read is rejected")
        since = len(log)
        config.write_text('{}')
        wait_for("BRIGHT_ERROR", lambda v: v == "", "explicit refresh clears read error", since=since)
        wait_for("BRIGHT_MAP", lambda v: v == {"HDMI-A-1": 8, "DP-2": 10}, "auto buses restored again", since=since)
        assert (home / "ddc-value-8").read_text() == (home / "ddc-value-10").read_text() == "50"
        calls = [json.loads(line) for line in (home / "ddc-calls").read_text().splitlines()]
        assert sum(args[0] == "setvcp" for args in calls) == 8, "Config edits must not change brightness"
        urls = (home / "curl-args").read_text().split()
        assert "wttr.in/London?format=j1" in urls, urls
        assert "wttr.in/New%20York?format=j1" in urls, urls  # one encoded argument, no shell
        # The sandbox deliberately has no PipeWire or D-Bus; these errors prove it stayed isolated.
        expected = ("quickshell.service.pipewire.loop: Failed to connect pipewire context",
                    "quickshell.network: Network will not work. Could not find an available backend")
        for e in expected:
            assert any(e in line for line in log), "harness may have reached the real session: " + e
        bad = [line for line in log if not any(e in line for e in expected) and any(marker in line for marker in (
            " ERROR", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration"))]
        assert not bad, "".join(bad)
        print("PASS: Config defaults, file creation, watched/atomic edits, zero, partial/invalid settings, bus overrides/reset")
        print("PASS: Desktop singleton startup, live timeout bindings and two-way DND wiring (stubbed commands)")
        print("PASS: Notifs toasts/history/badge/DND/dismiss/clear and media toasts; Weather fetch and "
              "location reload (stubbed curl); Sysmon live /proc and CPU sensor readings; Audio "
              "loads without PipeWire (stubbed pactl states); Net/Bt load without D-Bus; "
              "Brightness detect/read, rapid writes, partial failure and recovery (stubbed ddcutil)")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        reader.join(timeout=1)
        proc.stdout.close()
