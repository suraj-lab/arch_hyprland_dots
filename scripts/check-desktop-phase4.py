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
for command in ("Xvfb", "qs", "magick", "xdotool", "lua"):
    if not shutil.which(command):
        raise SystemExit(f"Missing test dependency: {command} (nothing installed)")

print(subprocess.run(["lua", "scripts/tests/test_super_tap.lua"], cwd=ROOT, check=True,
                     capture_output=True, text=True, timeout=30).stdout.strip())

with tempfile.TemporaryDirectory(prefix=".p4-", dir=ROOT) as tmp:
    home = Path(tmp)
    config_dir = home / ".config/quickshell"
    config_dir.mkdir(parents=True)
    runtime = home / "r"
    runtime.mkdir(mode=0o700)
    for name in ("services", "theme", "components"):
        shutil.copytree(ROOT / ".config/quickshell" / name, config_dir / name)
    # The pill's chips load Desktop, Audio etc. As in check-desktop-phase3.py, no real
    # controller, service or session command may run from the sandbox.
    (home / "bin").mkdir()
    for name, body in {"gamemoded": "printf 'gamemode is inactive\\n'", "pgrep": "exit 1",
                       "pkill": "exit 1", "hyprctl": "exit 1", "systemctl": "exit 1",
                       "hyprlock": "exit 1", "pactl": "exit 0", "curl": "exit 1",
                       "ddcutil": "exit 1"}.items():
        (home / "bin" / name).write_text("#!/bin/sh\n" + body + "\n")
        (home / "bin" / name).chmod(0o700)
    (config_dir / "scripts").mkdir()
    (config_dir / "scripts/desktop-gamemode.py").write_text('print(\'{"gameMode":false,"dnd":false}\')\n')
    # Xvfb has no layer shell, so its attached properties cannot be created there.
    # Check them statically in the real files, then drop them from the private copy.
    for name, namespace in (("frame/Frame.qml", '"quickshell-frame"'),
                            ("frame/Reserve.qml", '"quickshell-reserve-" + edge'),
                            ("pill/PillOverlay.qml", '"quickshell-pill"')):
        source = (ROOT / ".config/quickshell/components" / name).read_text()
        layer = "Overlay" if name.startswith("pill/") else "Top"
        # The pill takes keyboard focus only while a surface is open (Escape closes it).
        focus = ('surface !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None'
                 if name.startswith("pill/") else "WlrKeyboardFocus.None")
        for line in ("WlrLayershell.layer: WlrLayer." + layer, "WlrLayershell.namespace: " + namespace,
                     "WlrLayershell.keyboardFocus: " + focus):
            assert line in source, f"{name}: missing {line}"
        copy = config_dir / "components" / name
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
               QT_QPA_PLATFORM="xcb", QT_QUICK_BACKEND="software", QML_DISABLE_DISK_CACHE="1",
               PATH=str(home / "bin") + ":/usr/bin")
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

            empty = lambda v: v["layout"] == "classic" and v["frames"] == [] and v["pills"] == []
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
            # ---- 4.2 pill: a real pointer (xdotool) on the private display drives hover ----
            def pointer(x, y):
                subprocess.run(["xdotool", "mousemove", str(x), str(y)], env=env, check=True, timeout=5)

            def pill():
                return wait_state(lambda v: len(v["pills"]) == 1, "one pill")["pills"][0]

            def wait_pill(accept, what, timeout=3):
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    value = pill()
                    if accept(value):
                        return value
                    time.sleep(0.03)
                raise AssertionError(f"pill never reached: {what}; last {value}")

            pointer(400, 300)
            configure({"appearance": {"layout": "frame"}},
                      lambda v: len(v["pills"]) == 1 and v["pills"][0]["state"] == "rest", "pill at rest")
            rest = wait_pill(lambda v: v["state"] == "rest" and v["w"] == 230 and v["h"] == 30, "settled rest")
            win_top = 544                   # the pill's 56 px bottom strip (window is full-height)
            assert (rest["w"], rest["h"], rest["winH"]) == (230, 30, 600), rest
            assert rest["x"] == 285 and rest["y"] == rest["winH"] - 10 - 30, rest  # centred, on the frame edge
            assert rest["visible"] and rest["hoverExpand"] and rest["animate"], rest
            assert rest["collapseMs"] == 700, rest

            # Pixels at rest (shape image = overlay window, 800x600): rounded top corners and
            # concave shoulders joining the frame edge (baseY 46, shoulder radius 30-16 = 14).
            assert ipc("pillCapture").returncode == 0
            image = home / "pill.png"
            deadline = time.monotonic() + 5
            while not image.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            points = [(x, y + win_top) for x, y in
                      [(400, 30), (400, 10), (300, 20), (286, 17), (283, 45), (272, 33),
                       (265, 50), (285, 50), (514, 17), (517, 45), (528, 33)]]
            fmt = " ".join(f"%[fx:p{{{x},{y}}}.a]" for x, y in points)
            alpha = [round(float(v)) for v in subprocess.check_output(
                ["magick", str(image), "-format", fmt, "info:"], text=True).split()]
            assert alpha == [1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0], alpha

            # Bottom-edge dwell: passing through the hot strip does nothing; resting opens.
            pointer(60, 598); time.sleep(0.05); pointer(60, 300); time.sleep(0.4)
            assert pill()["state"] == "rest", "a pass through the bottom edge must not expand"
            pointer(60, 598)
            hover = wait_pill(lambda v: v["state"] == "hover" and v["w"] == 696 and v["h"] == 46,
                              "hover after the dwell")
            assert hover["x"] == 52 and hover["y"] == hover["winH"] - 10 - 46, hover
            pointer(400, 592); time.sleep(1.0)       # frame band under the pill (not the hot strip)
            assert pill()["state"] == "hover", "the frame band under the pill must count as the pill"
            pointer(400, win_top + 30); time.sleep(1.0)             # onto the pill: stays open
            assert pill()["state"] == "hover", "must stay open while the pointer is on the pill"
            pointer(400, 300)
            wait_pill(lambda v: v["state"] == "rest" and v["w"] == 230, "collapse after leaving")

            # IPC pin: stays open until the pointer has visited and left.
            assert ipc("pill", "open").returncode == 0
            wait_pill(lambda v: v["state"] == "hover" and v["pinned"], "pinned open")
            time.sleep(0.6)
            assert pill()["state"] == "hover", "an untouched pin must not collapse"
            pointer(400, win_top + 30); time.sleep(0.1); pointer(400, 300)
            wait_pill(lambda v: v["state"] == "rest" and not v["pinned"], "pin ends after a visit")
            assert ipc("pill", "toggle").returncode == 0
            wait_pill(lambda v: v["state"] == "hover", "toggle opens")
            assert ipc("pill", "toggle").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "toggle closes")

            # Fullscreen: nothing mapped; a pin is the peek; leaving fullscreen ends it.
            assert ipc("fullscreen", "true", "false").returncode == 0
            wait_pill(lambda v: v["state"] == "hidden" and not v["visible"], "hidden on fullscreen")
            assert ipc("pill", "open").returncode == 0
            peek = wait_pill(lambda v: v["state"] == "hover" and v["visible"], "peek over fullscreen")
            assert peek["collapseMs"] == 800, peek
            # Pointer never goes near it (the usual case over a game): hides after 800 ms.
            wait_pill(lambda v: v["state"] == "hidden" and not v["pinned"], "peek hides untouched")
            assert ipc("pill", "open").returncode == 0
            wait_pill(lambda v: v["state"] == "hover" and v["visible"], "peek again")
            assert ipc("fullscreen", "false", "false").returncode == 0
            wait_pill(lambda v: v["state"] == "rest" and not v["pinned"], "peek ends with fullscreen")

            # Rest-only monitor (the HDMI-A-1 default in settings.json): no dwell; click opens.
            configure({"appearance": {"layout": "frame"},
                       "monitors": {"HDMI-A-1": {"pill": {"hoverExpand": False}}}},
                      lambda v: True, "HDMI override")
            assert ipc("pillOn", "HDMI-A-1").returncode == 0
            wait_pill(lambda v: v["name"] == "HDMI-A-1" and not v["hoverExpand"], "rest-only pill")
            pointer(60, 598); time.sleep(0.6)
            assert pill()["state"] == "rest", "rest-only monitors must not expand on hover"
            pointer(450, win_top + 31)
            subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)
            wait_pill(lambda v: v["state"] == "hover", "click on the rest tab expands")
            pointer(400, 300)
            wait_pill(lambda v: v["state"] == "rest", "collapse after the click visit")
            assert ipc("pillOn", "DP-2").returncode == 0

            # ---- 4.3 surfaces: the classic views rise from the bar row ----
            assert ipc("pill", "unread").returncode == 0
            assert ipc("pill", "sound").returncode == 0
            snd = wait_pill(lambda v: v["state"] == "surface" and v["surface"] == "sound"
                            and v["tierTarget"] > 100 and v["tierH"] == v["tierTarget"] and v["w"] == 696,
                            "sound surface settled")
            # The surface grows from its chip (right half of the row), clamped inside the bar ends.
            inset = 16 + 22
            expect_x = round(snd["x"] + max(inset, min(snd["anchor"] - 200, snd["w"] - inset - 400)))
            assert snd["anchor"] > snd["w"] / 2 and snd["tierX"] == expect_x, snd
            assert snd["tierW"] == 400 and snd["tierY"] == snd["y"] - snd["tierH"], snd
            assert snd["x"] + inset <= snd["tierX"] and snd["tierX"] + 400 <= snd["x"] + snd["w"] - inset, snd
            assert snd["unread"] == 3, "opening Sound must not clear the notification badge"
            # Pixels: tier corners rounded (radius 26), concave joins into the bar top.
            (home / "pill.png").unlink(missing_ok=True)
            assert ipc("pillCapture").returncode == 0
            deadline = time.monotonic() + 5
            while not (home / "pill.png").exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            ty, by = snd["tierY"], snd["y"]          # tier top, bar top (window coords)
            sx0, sx1 = snd["tierX"], snd["tierX"] + 400
            pts = [(sx0 + 200, ty + 5), (sx0 + 200, ty - 3), (sx0 + 2, ty + 2), (sx0 + 15, ty + 13),
                   (sx0 - 10, by - 2), (sx0 - 20, by - 12), (sx0 - 1, by - 1), (sx1 + 10, by - 2),
                   (sx1 + 20, by - 12), (sx1 - 2, ty + 2)]
            fmt = " ".join(f"%[fx:p{{{x},{y}}}.a]" for x, y in pts)
            alpha = [round(float(v)) for v in subprocess.check_output(
                ["magick", str(home / "pill.png"), "-format", fmt, "info:"], text=True).split()]
            assert alpha == [1, 0, 0, 1, 1, 0, 1, 1, 0, 0], alpha
            pointer(400, 300); time.sleep(1.2)                 # a surface never auto-collapses
            assert pill()["state"] == "surface", "a surface must stay open without the pointer"
            assert ipc("pill", "notifs").returncode == 0      # switch directly
            nt = wait_pill(lambda v: v["surface"] == "notifs" and v["tierH"] == v["tierTarget"], "switch to notifs")
            assert nt["anchor"] != snd["anchor"], "each surface grows from its own chip"
            assert nt["unread"] == 0, "opening Notifications clears the badge"
            assert ipc("pill", "notifs").returncode == 0      # same surface again closes it
            closing = pill()
            assert closing["surface"] == "" and closing["tierX"] == nt["tierX"], "must close where it opened"
            closed = wait_pill(lambda v: v["surface"] == "" and v["tierH"] == 0, "re-open toggles closed")
            assert closed["tierX"] == nt["tierX"], "the tier must not jump while closing"
            assert ipc("pill", "system").returncode == 0
            wait_pill(lambda v: v["surface"] == "system" and v["tierH"] == v["tierTarget"] > 100, "system surface")
            # No window manager on Xvfb: keys go to the window under the pointer, so point at
            # the surface first (live, the pill takes focus on demand while a surface is open).
            sysv = pill()
            pointer(400, sysv["tierY"] + 40); time.sleep(0.2)
            top = subprocess.run(["xdotool", "getmouselocation", "--shell"], env=env, capture_output=True,
                                 text=True, timeout=5).stdout
            window = dict(line.split("=", 1) for line in top.split())["WINDOW"]
            subprocess.run(["xdotool", "windowfocus", "--sync", window], env=env, timeout=5)
            subprocess.run(["xdotool", "key", "--window", window, "Escape"], env=env, check=True, timeout=5)
            wait_pill(lambda v: v["surface"] == "", "Escape closes the surface")
            assert ipc("pill", "sound").returncode == 0
            wait_pill(lambda v: v["surface"] == "sound", "sound again")
            assert ipc("fullscreen", "true", "false").returncode == 0
            wait_pill(lambda v: v["state"] == "hidden" and v["surface"] == "", "fullscreen closes surfaces")
            assert ipc("fullscreen", "false", "false").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "back to rest")

            # Collapse delay setting: global, per monitor, invalid values fall back.
            configure({"appearance": {"layout": "frame"}, "pill": {"collapseDelayMs": 1500}},
                      lambda v: v["pills"] and v["pills"][0]["collapseMs"] == 1500, "global delay")
            configure({"appearance": {"layout": "frame"}, "pill": {"collapseDelayMs": 1500},
                       "monitors": {"DP-2": {"pill": {"collapseDelayMs": 0}}}},
                      lambda v: v["pills"] and v["pills"][0]["collapseMs"] == 0, "per-monitor delay")
            for bad in (-1, 5001, 1.5, "700", True):
                configure({"appearance": {"layout": "frame"}, "pill": {"collapseDelayMs": bad}},
                          lambda v: v["pills"] and v["pills"][0]["collapseMs"] == 700, f"invalid delay {bad!r}")

            # Animations off: the morph is instant.
            configure({"appearance": {"layout": "frame", "animations": False}},
                      lambda v: len(v["pills"]) == 1 and not v["pills"][0]["animate"], "animations off")
            assert ipc("pill", "open").returncode == 0
            assert pill()["w"] == 696, "no morph when animations are off"
            assert ipc("pill", "close").returncode == 0

            for invalid in ("invalid", True, 42, None):
                configure({"appearance": {"layout": invalid}}, empty, "invalid layout is classic")
            configure({}, empty, "removed sections return to classic")
            log.flush()
            lines = (home / "shell.log").read_text().splitlines()
            # No PipeWire or D-Bus in the sandbox: these errors prove it stayed isolated.
            isolated = ("quickshell.service.pipewire.loop: Failed to connect pipewire context",
                        "quickshell.network: Network will not work. Could not find an available backend")
            for expected in isolated:
                assert any(expected in line for line in lines), "sandbox may have reached the session: " + expected
            errors = [line for line in lines if not any(e in line for e in isolated) and any(
                word in line for word in (" ERROR", "TypeError:", "ReferenceError:", "Binding loop"))]
            assert not errors, "\n".join(errors)
            print("PASS: settings file present at startup is applied immediately; unrelated edits keep frames")
            print("PASS: classic/frame switch, fixed reserves, empty masks, per-monitor fullscreen and hotplug")
            print("PASS: classic-bar preview (no top reserve, no pill space)")
            print("PASS: rest-style override/reset, invalid settings, frame pixels on private Xvfb")
            print("PASS: pill rest geometry and shape pixels, edge dwell/pass-through, collapse, IPC pin/toggle,")
            print("      frame band counts as the pill, fullscreen hide + peek (hides untouched after 800 ms),")
            print("      rest-only click-to-expand, collapse-delay setting, animations off (real pointer on Xvfb)")
            print("PASS: surfaces: open/switch/re-open toggle, Escape, stays open, badge clears on Notifications only,")
            print("      fullscreen closes them, tier over its chip, tier shape pixels (rounded corners, concave joins)")
            print("PASS: layers, per-surface namespaces, keyboard focus only for an open surface (static; Xvfb has no layer shell)")
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
