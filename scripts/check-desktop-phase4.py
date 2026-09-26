#!/usr/bin/env python3
"""Phase 4.1 offline checks. Private Xvfb only; never use the running Wayland session.

Checks QML behavior and frame pixels, not Wayland exclusive-zone placement or VRR.
Requires the already-installed Xvfb, Quickshell and ImageMagick; installs nothing.
"""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
for command in ("Xvfb", "qs", "magick"):
    if not shutil.which(command):
        raise SystemExit(f"Missing test dependency: {command} (nothing installed)")

with tempfile.TemporaryDirectory(prefix=".p4-", dir=ROOT) as tmp:
    home = Path(tmp)
    config_dir = home / ".config/quickshell"
    config_dir.mkdir(parents=True)
    runtime = home / "r"
    runtime.mkdir(mode=0o700)
    for name in ("services", "theme", "components/frame"):
        shutil.copytree(ROOT / ".config/quickshell" / name, config_dir / name)
    # Xvfb has no layer shell, so its attached properties cannot be created there.
    # Check them statically in the real files, then drop them from the private copy.
    for name, namespace in (("Frame.qml", '"quickshell-frame"'), ("Reserve.qml", '"quickshell-reserve-" + edge')):
        source = (ROOT / ".config/quickshell/components/frame" / name).read_text()
        for line in ("WlrLayershell.layer: WlrLayer.Top", "WlrLayershell.namespace: " + namespace,
                     "WlrLayershell.keyboardFocus: WlrKeyboardFocus.None"):
            assert line in source, f"{name}: missing {line}"
        copy = config_dir / "components/frame" / name
        copy.write_text("\n".join(l for l in source.splitlines()
                                  if not l.strip().startswith("WlrLayershell.")) + "\n")
    fixture = config_dir / "shell.qml"
    fixture.write_text((ROOT / "scripts/tests/frame-shell.qml").read_text().replace(
        "../../.config/quickshell/", ""))
    settings = config_dir / "settings.json"
    # Regression: settings present at startup used to be ignored until the file changed.
    settings.write_text(json.dumps({"appearance": {"layout": "frame"}}))
    env = dict(os.environ, HOME=tmp, XDG_CONFIG_HOME=str(home / ".config"),
               XDG_CACHE_HOME=str(home / ".cache"), XDG_DATA_HOME=str(home / ".local/share"),
               XDG_STATE_HOME=str(home / ".state"), XDG_RUNTIME_DIR=str(runtime),
               DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent",
               DBUS_SYSTEM_BUS_ADDRESS="unix:path=/nonexistent",
               QT_QPA_PLATFORM="xcb", QT_QUICK_BACKEND="software", QML_DISABLE_DISK_CACHE="1")
    for key in ("HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY", "XAUTHORITY",
                "SESSION_MANAGER", "SWAYSOCK", "I3SOCK", "PIPEWIRE_REMOTE", "PIPEWIRE_RUNTIME_DIR",
                "PULSE_SERVER"):
        env.pop(key, None)
    # A private display is needed: Quickshell has no offscreen PanelWindow backend.
    read_fd, write_fd = os.pipe()
    shell = None
    with (home / "xvfb.log").open("w+") as xlog, (home / "shell.log").open("w+") as log:
        display = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0",
                                    "800x600x24", "-nolisten", "tcp"],
                                   env=env, pass_fds=(write_fd,), stdout=xlog, stderr=xlog)
        os.close(write_fd)
        try:
            if not select.select([read_fd], [], [], 5)[0]:
                raise AssertionError("Private Xvfb did not start")
            number = os.read(read_fd, 32).decode().strip()
            assert number.isdigit(), "Xvfb did not return a private display number"
            env["DISPLAY"] = ":" + number
            shell = subprocess.Popen(["qs", "--no-color", "--path", str(fixture)],
                                     cwd=ROOT, env=env, stdout=log, stderr=log)

            def ipc(method, *args):
                return subprocess.run(["qs", "ipc", "--path", str(fixture), "call", "frameTest", method,
                                       *args], cwd=ROOT, env=env, capture_output=True, text=True, timeout=5)

            def wait_state(accept, what):
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    result = ipc("status")
                    if result.returncode == 0:
                        value = json.loads(result.stdout)
                        if accept(value):
                            return value
                    if shell.poll() is not None:
                        break
                    time.sleep(0.05)
                raise AssertionError("No state: " + what)

            def configure(data, accept, what):
                replacement = settings.with_suffix(".tmp")
                replacement.write_text(json.dumps(data))
                replacement.replace(settings)
                return wait_state(accept, what)

            def check_frame(frame, visible, bottom, top=True):
                assert frame["visible"] == visible and frame["bottom"] == bottom, frame
                assert frame["maskEmpty"] and frame["ignoreReserves"] and not frame["focus"], frame
                reserves = {r["edge"]: r for r in frame["reserves"]}
                assert set(reserves) == {"top", "bottom", "left", "right"}, reserves
                opposite = {"top": "bottom", "bottom": "top", "left": "right", "right": "left"}
                for edge, reserve in reserves.items():
                    assert reserve["visible"] == (visible and (top or edge != "top")), reserve
                    assert reserve["zone"] == (bottom if edge == "bottom" else 10), reserve
                    assert reserve["maskEmpty"] and not reserve["focus"], reserve
                    assert reserve["anchors"] == {e: e != opposite[edge] for e in opposite}, reserve

            empty = lambda v: v["layout"] == "classic" and v["frames"] == []
            wait_state(lambda v: v["layout"] == "frame" and len(v["frames"]) == 2, "frame read at startup")
            configure({}, empty, "classic by default: no extra windows")
            state = configure({"appearance": {"layout": "frame"}},
                              lambda v: len(v["frames"]) == 2 and all(f["visible"] for f in v["frames"]),
                              "two frames in frame mode")
            for frame in state["frames"]:
                check_frame(frame, True, 40)
            # Unrelated edits must not rebuild the frame windows.
            builds = state["builds"]
            configure({"appearance": {"layout": "frame"}, "idle": {"lockSec": 123}},
                      lambda v: len(v["frames"]) == 2, "unrelated edit")
            time.sleep(0.5)
            assert wait_state(lambda v: True, "status")["builds"] == builds, "frames rebuilt by unrelated edit"
            # Actual rendering on the private display: opaque edges, transparent hole,
            # rounded inner corners. Never capture the user's desktop.
            time.sleep(0.2)
            assert ipc("capture").returncode == 0
            image = home / "frame.png"
            deadline = time.monotonic() + 5
            while not image.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            width, height = map(int, subprocess.check_output(
                ["magick", str(image), "-format", "%w %h", "info:"], text=True).split())
            assert (width, height) == (800, 600), (width, height)
            points = [(0, 0), (400, 300), (9, 300), (11, 300), (10, 10),
                      (32, 10), (799, 599), (790, 590)]
            fmt = " ".join(f"%[fx:p{{{x},{y}}}.a]" for x, y in points)
            alpha = [float(v) for v in subprocess.check_output(
                ["magick", str(image), "-format", fmt, "info:"], text=True).split()]
            assert alpha == [1, 0, 1, 0, 1, 0, 1, 1], alpha

            assert ipc("fullscreen", "true", "false").returncode == 0
            state = wait_state(lambda v: not v["frames"][0]["visible"], "main fullscreen")
            check_frame(state["frames"][0], False, 40)
            check_frame(state["frames"][1], True, 40)
            assert ipc("fullscreen", "false", "true").returncode == 0
            state = wait_state(lambda v: v["frames"][0]["visible"] and not v["frames"][1]["visible"],
                               "secondary fullscreen")
            check_frame(state["frames"][0], True, 40)
            check_frame(state["frames"][1], False, 40)
            assert ipc("fullscreen", "false", "false").returncode == 0

            overrides = {"appearance": {"layout": "frame"}, "pill": {"restStyle": "handle"},
                         "monitors": {"HDMI-A-1": {"pill": {"restStyle": "tab"}}}}
            state = configure(overrides, lambda v: v["frames"][0]["bottom"] == 16, "rest-style overrides")
            check_frame(state["frames"][0], True, 16)
            check_frame(state["frames"][1], True, 40)
            assert ipc("secondary", "false").returncode == 0
            wait_state(lambda v: len(v["frames"]) == 1, "monitor removal")
            assert ipc("secondary", "true").returncode == 0
            state = wait_state(lambda v: len(v["frames"]) == 2, "monitor re-add")
            check_frame(state["frames"][1], True, 40)
            state = configure({"appearance": {"layout": "frame"}, "pill": {"restStyle": "bad"}},
                              lambda v: all(f["bottom"] == 40 for f in v["frames"]), "invalid rest-style fallback")
            for frame in state["frames"]:
                check_frame(frame, True, 40)
            # Preview beside the classic bar: no top reserve, bottom is frame thickness only.
            assert ipc("classic", "true").returncode == 0
            state = wait_state(lambda v: all(f["bottom"] == 10 for f in v["frames"]), "classic-bar preview")
            for frame in state["frames"]:
                check_frame(frame, True, 10, top=False)
            assert ipc("classic", "false").returncode == 0
            wait_state(lambda v: all(f["bottom"] == 40 for f in v["frames"]), "full frame restored")
            for invalid in ("invalid", True, 42, None):
                configure({"appearance": {"layout": invalid}}, empty, "invalid layout is classic")
            configure({}, empty, "removed sections return to classic")
            log.flush()
            errors = [line for line in (home / "shell.log").read_text().splitlines()
                      if any(word in line for word in (" ERROR", "TypeError:", "ReferenceError:", "Binding loop"))]
            assert not errors, "\n".join(errors)
            print("PASS: settings file present at startup is applied immediately; unrelated edits keep frames")
            print("PASS: classic/frame switch, fixed reserves, empty masks, per-monitor fullscreen and hotplug")
            print("PASS: classic-bar preview (no top reserve, no pill space)")
            print("PASS: rest-style override/reset, invalid settings, frame pixels on private Xvfb")
            print("PASS: Top layer, per-surface namespaces and no keyboard focus (static; Xvfb has no layer shell)")
            print("NOT TESTED: live Wayland exclusive zones, click-through, direct scanout or VRR")
        except Exception:
            log.flush()
            print((home / "shell.log").read_text()[-6000:])
            raise
        finally:
            os.close(read_fd)
            for proc in (shell, display):
                if proc is not None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait()
