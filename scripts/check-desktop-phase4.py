#!/usr/bin/env python3
"""Phase 4.1 offline checks. Private Xvfb only; never use the running Wayland session.

Checks QML behavior and frame pixels, not Wayland exclusive-zone placement or VRR.
Requires the already-installed Xvfb, Quickshell and ImageMagick; installs nothing.
"""
import json
import os
from pathlib import Path
import select
import signal
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
for command in ("Xvfb", "xvfb-run", "xauth", "qs", "magick", "xdotool", "lua", "dbus-run-session"):
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
                       "pkill": "exit 1", "systemctl": "exit 1",
                       # Updates (6.4): fake sources; every call is logged to prove they are read-only.
                       "checkupdates": 'echo "checkupdates $*" >> "$HOME/update-calls"; '
                                       'printf "bash 5.3.15-2 -> 5.3.20-2\\ngspell 1.14.4 -> 1.14.5\\n"',
                       "flatpak": 'echo "flatpak $*" >> "$HOME/update-calls"; [ "$1" = remote-ls ] && echo com.example.App',
                       "paru": 'echo "paru $*" >> "$HOME/update-calls"; '
                               'if [ "$1" = -Qua ]; then echo "ani-cli 5.0-1 -> 5.1-1"; exit 0; fi; exit 1',
                       # Devices (6.3): lsblk reads $HOME/lsblk.json; udisksctl logs calls, `monitor`
                       # idles, `power-off` empties the list (the stick is gone); thunar logs.
                       "lsblk": 'cat "$HOME/lsblk.json"',
                       "udisksctl": '[ "$1" = monitor ] && { while kill -0 $PPID 2>/dev/null; do sleep 0.5; done; exit 0; }; echo "$*" >> "$HOME/udisks-calls"; '
                                    '[ "$1" = power-off ] && echo \'{"blockdevices":[]}\' > "$HOME/lsblk.json"; exit 0',
                       "thunar": 'echo "$*" >> "$HOME/thunar-calls"',
                       # Cheatsheet (5.2) reads `hyprctl binds -j`; settings (6.5b) reads `hyprctl monitors -j`.
                       "hyprctl": 'if [ "$*" = "binds -j" ]; then cat "$HOME/binds.json"; '
                                  'elif [ "$*" = "monitors -j" ]; then cat "$HOME/monitors.json"; else exit 1; fi',
                       # Settings (6.5b) default apps: query answers from $HOME/mime-defaults;
                       # `default` logs the whole argv and updates the first type's answer.
                       "xdg-mime": 'if [ "$1" = query ]; then '
                                   'g=$(grep "^$3=" "$HOME/mime-defaults" 2>/dev/null | head -1); '
                                   '[ -n "$g" ] && printf "%s\\n" "${g#*=}"; '
                                   'elif [ "$1" = default ]; then '
                                   't=$3; printf "%s\\n" "$*" >> "$HOME/xdg-mime-calls"; '
                                   'grep -v "^$t=" "$HOME/mime-defaults" > "$HOME/mime-defaults.tmp" 2>/dev/null; '
                                   'mv "$HOME/mime-defaults.tmp" "$HOME/mime-defaults"; '
                                   'printf "%s=%s\\n" "$t" "$2" >> "$HOME/mime-defaults"; '
                                   'else exit 1; fi',
                       "hyprlock": "exit 1", "pactl": "exit 0", "curl": "exit 1",
                       "ddcutil": "exit 1",
                       # Launcher (5.1): fake calculator, clipboard history and wl-copy.
                       "qalc": 'printf "%s\\n" "$@" > "$HOME/qalc-args"; echo "\u221242"',   # real qalc: U+2212 minus
                       "wl-copy": 'if [ "$1" = "--" ]; then printf "%s" "$2"; else cat; fi > "$HOME/copied"',
                       "cliphist": 'case "$1" in\n'
                                   'list) printf "3\\thello clipboard\\n2\\t[[ binary data 1 KiB png 4x4 ]]\\n'
                                   '1\\tsecond entry\\n" | if [ -f "$HOME/clip-deleted" ];'
                                   ' then grep -vxF -f "$HOME/clip-deleted"; else cat; fi ;;\n'
                                   'decode) IFS= read -r line; if [ "${line%%\t*}" = 2 ]; then cat "$HOME/clip.png";'
                                   ' else printf "%s" "${line#*\t}"; fi ;;\n'
                                   'delete) IFS= read -r line; printf "%s\\n" "$line" >> "$HOME/clip-deleted" ;;\n'
                                   'esac'}.items():
        (home / "bin" / name).write_text("#!/bin/sh\n" + body + "\n")
        (home / "bin" / name).chmod(0o700)
    # Devices (6.3): one USB stick, its partition mounted where udisks mounts things.
    (home / "lsblk.json").write_text(json.dumps({"blockdevices": [{
        "name": "sdb", "path": "/dev/sdb", "type": "disk", "hotplug": True, "rm": True, "size": "28.9G",
        "label": None, "fstype": None, "mountpoints": [None], "vendor": "SanDisk", "model": "Ultra Fit",
        "tran": "usb", "children": [{
            "name": "sdb1", "path": "/dev/sdb1", "type": "part", "hotplug": True, "rm": True, "size": "28.9G",
            "label": "STICK", "fstype": "exfat", "mountpoints": ["/run/media/suraj/STICK"]}]}]}))
    # Launcher (5.1): a findable app whose launch leaves a mark, and a clipboard image.
    apps = home / ".local/share/applications"
    apps.mkdir(parents=True)
    (apps / "zyxtest.desktop").write_text("[Desktop Entry]\nType=Application\nName=Zyxtest Launcher\n"
                                         f"Exec=touch {home}/launched\n")
    subprocess.run(["magick", "-size", "4x4", "xc:#ff00ff", str(home / "clip.png")], check=True)
    bind = lambda mods, key, text: {"modmask": mods, "key": key, "description": text, "has_description": bool(text),
                                    "dispatcher": "__lua", "arg": "1"}
    (home / "binds.json").write_text(json.dumps([
        bind(64, "return", "Apps: Terminal"), bind(64, "C", "Windows: Close"), bind(64, "E", "Apps: File manager"),
        bind(65, "left", "Windows: Move left"), bind(64, "SUPER_L", "Shell: Double-tap Super expands the pill"),
        bind(64, "slash", "Shell: Keybind cheatsheet"), bind(0, "XF86AudioMute", "Media: Mute audio")]))
    (config_dir / "scripts").mkdir()
    (config_dir / "scripts/desktop-gamemode.py").write_text('print(\'{"gameMode":false,"dnd":false}\')\n')
    # Settings (6.5b): the two real monitors (sorted by x in the surface), the live default
    # apps, and a local mimeinfo.cache with an extra resolvable browser candidate.
    (home / "monitors.json").write_text(json.dumps([
        {"name": "DP-2", "description": "Dell Inc. AW3423DWF 70742S3", "width": 3440, "height": 1440,
         "refreshRate": 164.89999, "x": 1920, "y": -400, "scale": 1, "vrr": False, "focused": True},
        {"name": "HDMI-A-1", "description": "ViewSonic Corporation VX2476 Series UPA213310203", "width": 1920,
         "height": 1080, "refreshRate": 74.973, "x": 0, "y": 0, "scale": 1, "vrr": False, "focused": False}]))
    (home / "mime-defaults").write_text(
        "x-scheme-handler/https=firefox.desktop\n"
        "inode/directory=thunar.desktop\n"
        "text/plain=codium.desktop\n"
        "image/png=viewnior.desktop\n")
    (apps / "mimeinfo.cache").write_text(
        "[MIME Cache]\n"
        "x-scheme-handler/https=firefox.desktop;zyxtest.desktop;\n"
        "inode/directory=thunar.desktop;\n"
        "text/plain=codium.desktop;\n"
        "image/png=viewnior.desktop;\n")
    # Xvfb has no layer shell, so its attached properties cannot be created there.
    # Check them statically in the real files, then drop them from the private copy.
    for name, namespace in (("frame/Frame.qml", '"quickshell-frame"'),
                            ("frame/Reserve.qml", '"quickshell-reserve-" + edge'),
                            ("pill/PillOverlay.qml", '"quickshell-pill"')):
        source = (ROOT / ".config/quickshell/components" / name).read_text()
        layer = "Overlay" if name.startswith("pill/") else "Top"
        # The pill takes keyboard focus only while a surface is open (Escape closes it);
        # exclusively for the launcher, which is typed into at once.
        focus = ('surface === "launcher" || surface === "cheatsheet" ? WlrKeyboardFocus.Exclusive : '
                 'surface !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None'
                 if name.startswith("pill/") else "WlrKeyboardFocus.None")
        for line in ("WlrLayershell.layer: WlrLayer." + layer, "WlrLayershell.namespace: " + namespace,
                     "WlrLayershell.keyboardFocus: " + focus):
            assert line in source, f"{name}: missing {line}"
        copy = config_dir / "components" / name
        copy.write_text("\n".join(l for l in source.splitlines()
                                  if not l.strip().startswith("WlrLayershell.")) + "\n")
    # 6.1 polkit prompt: an overlay taking the keyboard exclusively (checked here, stripped below).
    source = (ROOT / ".config/quickshell/components/PolkitDialog.qml").read_text()
    for line in ("WlrLayershell.layer: WlrLayer.Overlay", 'WlrLayershell.namespace: "quickshell-polkit"',
                 "WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive"):
        assert line in source, f"PolkitDialog.qml: missing {line}"
    (config_dir / "components/PolkitDialog.qml").write_text(
        "\n".join(l for l in source.splitlines() if not l.strip().startswith("WlrLayershell.")) + "\n")
    shell_src = (ROOT / ".config/quickshell/shell.qml").read_text()
    assert shell_src.count("PolkitAgent {") == 1 and "PolkitDialog { flow: polkitAgent.flow" in shell_src, \
        "shell.qml: exactly one polkit agent, feeding the dialog"
    fixture = config_dir / "shell.qml"
    fixture.write_text((ROOT / "scripts/tests/frame-shell.qml").read_text().replace(
        "../../.config/quickshell/", ""))
    settings = config_dir / "settings.json"
    # Regression: settings present at startup used to be ignored until the file changed.
    # Handle, because tab is the default and would pass either way.
    settings.write_text(json.dumps({"pill": {"restStyle": "handle"}}))
    env = dict(os.environ, LC_ALL="C.UTF-8", HOME=tmp, XDG_CONFIG_HOME=str(home / ".config"),
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
    # -displayfd can steal Hyprland's filesystem socket when its abstract socket is
    # disabled. xvfb-run -a respects display locks (do not replace -a with -d).
    sockets = {p: p.lstat().st_ino for p in Path("/tmp/.X11-unix").glob("*")}
    shell = None
    with (home / "shell.log").open("w+") as log:
        # Publish the private environment, then keep Xvfb alive until stdin closes.
        # Let xvfb-run exit normally so it removes its server and temporary auth file.
        display = subprocess.Popen(["xvfb-run", "-a", "-s", "-screen 0 800x600x24",
                                    "-e", str(home / "xvfb.log"), "sh", "-c",
                                    'printf "%s\\n%s\\n" "$DISPLAY" "$XAUTHORITY"; cat >/dev/null'],
                                   env=dict(env, TMPDIR=tmp), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=log, text=True, start_new_session=True)
        try:
            if not select.select([display.stdout], [], [], 10)[0]:
                raise AssertionError("Private Xvfb did not start")
            env["DISPLAY"] = display.stdout.readline().strip()
            env["XAUTHORITY"] = display.stdout.readline().strip()
            assert env["DISPLAY"].startswith(":") and env["DISPLAY"][1:].isdigit(), "Invalid private display"
            assert env["DISPLAY"] != os.environ.get("DISPLAY"), "Xvfb must not use the desktop display"
            assert Path(env["XAUTHORITY"]).is_file(), "Missing private X authority file"
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

            wait_state(lambda v: len(v["frames"]) == 2 and all(f["bottom"] == 16 for f in v["frames"]),
                       "handle rest style read at startup")
            configure({}, lambda v: len(v["frames"]) == 2 and all(f["bottom"] == 40 for f in v["frames"]),
                      "tab rest style by default")
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
            # Only the spacer may stretch (a nested layout, e.g. the tray, fills by default and
            # used to push CPU/RAM into the centre, under the centre text).
            stretched = [s for s in hover["rowItems"] if s[1] - s[0] > s[2] + 1]
            assert hover["rowItems"] and not stretched, hover["rowItems"]
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
            # Handle rest style (6 px): the click target includes a margin and the screen edge
            # under it, but not the rest of the bottom edge.
            configure({"appearance": {"layout": "frame"}, "pill": {"restStyle": "handle"},
                       "monitors": {"HDMI-A-1": {"pill": {"hoverExpand": False}}}},
                      lambda v: v["pills"] and v["pills"][0]["handle"], "rest-only handle")
            wait_pill(lambda v: v["state"] == "rest" and v["h"] == 6, "handle at rest")
            for x, y, what in ((400, 599, "the screen edge under the handle"), (460, win_top + 32, "just above the handle")):
                pointer(x, y); time.sleep(0.2)
                subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)
                wait_pill(lambda v: v["state"] == "hover", f"click on {what} expands")
                pointer(400, 300)
                wait_pill(lambda v: v["state"] == "rest", "collapse after the click visit")
            pointer(120, 599); time.sleep(0.2)
            subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)
            time.sleep(0.4)
            assert pill()["state"] == "rest", "a click elsewhere on the bottom edge must not expand"
            configure({"appearance": {"layout": "frame"},
                       "monitors": {"HDMI-A-1": {"pill": {"hoverExpand": False}}}},
                      lambda v: v["pills"] and not v["pills"][0]["handle"], "back to the tab")
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
            # While the tier is still visible it must stay where it opened (sampled per frame).
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                v = pill()
                if v["tierH"] == 0:
                    break
                assert v["tierX"] == nt["tierX"], f"the tier moved while closing: {v}"
            wait_pill(lambda v: v["surface"] == "" and v["tierH"] == 0, "re-open toggles closed")
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

            # ---- 4.4 dashboard: from rest the bar widens first, then the tier rises ----
            assert pill()["state"] == "rest"
            assert ipc("pill", "dashboard").returncode == 0
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                v = pill()
                assert v["w"] >= v["hoverW"] or v["tierH"] == 0, f"tier rose before the bar was wide: {v}"
                if v["tierH"] > 0:
                    break
                time.sleep(0.01)
            dash = wait_pill(lambda v: v["surface"] == "dashboard" and v["tierH"] == v["tierTarget"] == 420,
                             "dashboard settled at 920x420 (clamped on a small screen)")
            assert dash["tierW"] == min(920, dash["hoverW"] - 2 * (16 + 22)) and dash["dashTab"] == "dashboard", dash
            assert dash["x"] + 38 <= dash["tierX"] and dash["tierX"] + dash["tierW"] <= dash["x"] + dash["w"] - 38, dash
            assert ipc("pill", "media").returncode == 0       # IPC media: Media tab, no close
            wait_pill(lambda v: v["surface"] == "dashboard" and v["dashTab"] == "media", "media tab")
            assert ipc("pill", "media").returncode == 0       # same element again closes
            wait_pill(lambda v: v["surface"] == "" and v["tierH"] == 0, "media toggles closed")
            assert ipc("pill", "dashboard").returncode == 0
            wait_pill(lambda v: v["dashTab"] == "dashboard" and v["tierH"] == 420, "clock opens the Dashboard tab")
            assert ipc("pill", "sound").returncode == 0       # switch to a narrow surface
            wait_pill(lambda v: v["surface"] == "sound" and v["tierW"] == 400, "switch to sound")
            assert ipc("pill", "close").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "closed")

            # ---- 4.5 edge drawers: toasts from the top-right corner, OSD from the right edge ----
            def drawer_alpha(points):
                (home / "drawers.png").unlink(missing_ok=True)
                assert ipc("drawerCapture").returncode == 0
                deadline = time.monotonic() + 5
                while not (home / "drawers.png").exists() and time.monotonic() < deadline:
                    time.sleep(0.05)
                time.sleep(0.1)
                fmt = " ".join(f"%[fx:p{{{px},{py}}}.a]" for px, py in points)
                return [round(float(a)) for a in subprocess.check_output(
                    ["magick", str(home / "drawers.png"), "-format", fmt, "info:"], text=True).split()]

            def settled(key, accept, what):
                last = None
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    v = pill()
                    if accept(v) and last is not None and v[key] == last[key]:
                        return v
                    last = v
                    time.sleep(0.1)
                raise AssertionError(f"{what} never settled; last {last}")

            idle = pill()
            assert idle["toasts"] == 0 and idle["toast"][3] == 0 and idle["osd"][2] == 0, idle
            assert ipc("toast", "2", "0").returncode == 0      # timeout 0: stays until dismissed
            dr = settled("toast", lambda v: v["toasts"] == 2 and v["toast"][3] > 100, "toast drawer")
            assert dr["toast"][:3] == [398, 10, 392], dr         # in the top-right corner, inside the frame
            y1 = 10 + dr["toast"][3]
            # Inside; beyond the top shoulder; top shoulder fillet vs hollow; rounded bottom-left
            # corner vs inside it; right-edge shoulder fillet vs hollow; below the drawer.
            assert drawer_alpha([(600, 30), (368, 15), (396, 12), (380, 28), (400, y1 - 2), (410, y1 - 10),
                                 (788, y1 + 2), (775, y1 + 15), (500, y1 + 5)]) == [1, 0, 1, 0, 0, 1, 1, 0, 0]
            assert pill()["state"] == "rest", "a toast must not expand the pill"
            assert ipc("toast", "3", "400").returncode == 0      # at most 4 stacked; timed ones go
            wait_pill(lambda v: v["toasts"] == 4, "four toasts at most")
            wait_pill(lambda v: v["toasts"] == 1, "timed toasts dismissed")
            assert ipc("toastDismiss").returncode == 0           # as the toast's close button does
            wait_pill(lambda v: v["toasts"] == 0 and v["toast"][3] == 0, "drawer closes with the last toast")

            assert ipc("osd", "volume").returncode == 0
            od = settled("osd", lambda v: v["osd"][2] == 52, "OSD tab")
            assert od["osd"] == [738, 190, 52, 220] and od["osdKind"] == "volume", od   # right edge, centred
            # Inside; left of the tab; top shoulder fillet vs hollow; rounded top-left corner.
            assert drawer_alpha([(760, 300), (730, 300), (788, 188), (775, 175), (739, 191)]) == [1, 0, 1, 0, 0]
            wait_pill(lambda v: not v["osdShown"] and v["osd"][2] == 0, "OSD hides after 2 s", timeout=4)
            assert ipc("osd", "mic").returncode == 0
            wait_pill(lambda v: v["osdKind"] == "mic" and v["osd"][2] == 52, "mic OSD")
            assert ipc("fullscreen", "true", "false").returncode == 0   # drawers hide with the pill
            wait_pill(lambda v: not v["visible"], "hidden on fullscreen")
            assert ipc("fullscreen", "false", "false").returncode == 0
            wait_pill(lambda v: v["visible"] and v["state"] == "rest", "back from fullscreen")

            # ---- 5.1 launcher: apps, "=" calculator, ">" actions, clipboard; keyboard only ----
            def focus_at(x, y):   # keys go to the window under the pointer (no WM on Xvfb)
                pointer(x, y); time.sleep(0.2)
                top = subprocess.run(["xdotool", "getmouselocation", "--shell"], env=env, capture_output=True,
                                     text=True, timeout=5).stdout
                win = dict(line.split("=", 1) for line in top.split())["WINDOW"]
                subprocess.run(["xdotool", "windowfocus", "--sync", win], env=env, timeout=5)
                return win

            def focus_surface():
                return focus_at(400, pill()["tierY"] + 30)   # over the search field

            def keys(win, *names):
                subprocess.run(["xdotool", "key", "--window", win, *names], env=env, check=True, timeout=5)

            def type_text(win, text):
                subprocess.run(["xdotool", "type", "--window", win, "--delay", "30", text], env=env,
                               check=True, timeout=10)

            def open_launcher(name="launcher"):
                assert ipc("pill", name).returncode == 0
                v = wait_pill(lambda v: v["surface"] == "launcher" and v["tierH"] == v["tierTarget"] > 0, name)
                return v, focus_surface()

            def wait_file(path, expected, timeout=3):
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    if path.exists() and path.read_bytes() == expected:
                        return
                    time.sleep(0.05)
                raise AssertionError(f"{path}: {path.read_bytes() if path.exists() else 'missing'!r}, wanted {expected!r}")

            lv, win = open_launcher()
            assert lv["tierW"] == min(640, lv["hoverW"] - 76) and lv["tierH"] == 470, lv   # 640x470, clamped
            assert lv["launcher"]["mode"] == "apps" and lv["launcher"]["query"] == "", lv
            type_text(win, "zyxtest")
            wait_pill(lambda v: v["launcher"]["query"] == "zyxtest" and v["launcher"]["count"] == 1, "app found")
            keys(win, "Return")
            wait_pill(lambda v: v["surface"] == "", "launching closes the launcher")
            wait_file(home / "launched", b"")

            _, win = open_launcher()                      # reopens empty
            assert pill()["launcher"]["query"] == ""
            type_text(win, "=1+2")
            wait_pill(lambda v: v["launcher"]["mode"] == "calc" and v["launcher"]["first"] == "\u221242", "calculator")
            wait_file(home / "qalc-args", b"-t\n--\n1+2\n")   # terse; no -e (that downloads exchange rates)
            keys(win, "Return")
            wait_pill(lambda v: v["surface"] == "", "Enter copies the result and closes")
            wait_file(home / "copied", b"-42")                # pasted with a plain minus

            _, win = open_launcher()
            type_text(win, ">reb")
            wait_pill(lambda v: v["launcher"]["mode"] == "actions" and v["launcher"]["count"] == 1, "reboot action")
            keys(win, "Return")
            armed = wait_pill(lambda v: v["launcher"]["armed"] == "reboot", "first Enter arms reboot")
            assert armed["surface"] == "launcher" and armed["lastAction"] == "", armed
            keys(win, "Return")
            wait_pill(lambda v: v["surface"] == "" and v["lastAction"] == "reboot", "second Enter runs it after closing")
            _, win = open_launcher()
            type_text(win, ">power")
            keys(win, "Return")
            wait_pill(lambda v: v["launcher"]["armed"] == "poweroff", "power off armed")
            time.sleep(3.3)
            assert pill()["launcher"]["armed"] == "" and pill()["lastAction"] == "reboot", "arming expires after 3 s"
            keys(win, "ctrl+a", "BackSpace")
            type_text(win, ">caff")
            keys(win, "Return")                           # not destructive: one Enter
            wait_pill(lambda v: v["surface"] == "" and v["lastAction"] == "caffeine", "caffeine action")

            _, win = open_launcher("clipboard")
            cb = wait_pill(lambda v: v["launcher"]["mode"] == "clipboard" and v["launcher"]["count"] == 3, "clipboard")
            assert cb["launcher"]["first"] == "hello clipboard", cb
            wait_file(runtime / "quickshell-clip/2.png", (home / "clip.png").read_bytes())   # image thumbnail
            keys(win, "Delete")                           # empty search, cursor at the end: delete the entry
            wait_pill(lambda v: v["launcher"]["count"] == 2 and v["launcher"]["first"].startswith("[[ binary"),
                      "Delete removes the entry")
            wait_file(home / "clip-deleted", b"3\thello clipboard\n")
            type_text(win, "second")
            wait_pill(lambda v: v["launcher"]["count"] == 1, "typing filters the clipboard")
            keys(win, "Return")
            wait_pill(lambda v: v["surface"] == "", "Enter copies the entry and closes")
            wait_file(home / "copied", b"second entry")
            assert ipc("pill", "launcher").returncode == 0
            wait_pill(lambda v: v["surface"] == "launcher" and v["launcher"]["mode"] == "apps", "launcher")
            assert ipc("pill", "clipboard").returncode == 0   # Super+V over the launcher switches to the clipboard
            wait_pill(lambda v: v["surface"] == "launcher" and v["launcher"]["mode"] == "clipboard", "switch")
            assert ipc("pill", "clipboard").returncode == 0   # Super+V again closes
            wait_pill(lambda v: v["surface"] == "" and v["tierH"] == 0, "Super+V toggles")
            win = open_launcher()[1]
            keys(win, "Escape")
            wait_pill(lambda v: v["surface"] == "", "Escape closes the launcher")

            # ---- 5.2 cheatsheet: hyprctl binds -j, grouped by description prefix, filter ----
            assert ipc("pill", "cheatsheet").returncode == 0
            cs = wait_pill(lambda v: v["surface"] == "cheatsheet" and v["tierH"] == v["tierTarget"] > 0
                           and v["sheet"]["groups"], "cheatsheet open")
            # 920x520, clamped to the bar and to the screen height (600 here: 600 - 10 - 46 - 60 = 484)
            assert cs["tierW"] == min(920, cs["hoverW"] - 76) and cs["tierH"] == min(520, cs["winH"] - 116), cs
            assert cs["sheet"]["groups"] == ["Apps", "Windows", "Shell", "Media"], cs["sheet"]
            assert cs["sheet"]["items"] == 7 and cs["sheet"]["other"] == 0, cs["sheet"]
            win = focus_surface()
            type_text(win, "file")
            wait_pill(lambda v: v["sheet"]["shown"] == ["Apps"] and v["sheet"]["items"] == 1, "filter")
            keys(win, "Escape")
            wait_pill(lambda v: v["surface"] == "", "Escape closes the cheatsheet")
            assert ipc("pill", "cheatsheet").returncode == 0      # reopens unfiltered
            wait_pill(lambda v: v["surface"] == "cheatsheet" and v["sheet"]["query"] == ""
                      and len(v["sheet"]["shown"]) == 4, "reopened unfiltered")
            assert ipc("pill", "cheatsheet").returncode == 0      # Super+/ again closes
            wait_pill(lambda v: v["surface"] == "" and v["tierH"] == 0, "Super+/ toggles")

            # ---- 6.4 updates: read-only checks, badge, surface; nothing upgrades on its own ----
            def updates(method):
                return subprocess.run(["qs", "ipc", "--path", str(fixture), "call", "updates", method], env=env,
                                      capture_output=True, text=True, timeout=5)
            assert updates("check").returncode == 0
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                st = json.loads(updates("status").stdout)
                if not st["checking"] and st["total"] == 4:
                    break
                time.sleep(0.1)
            assert st["total"] == 4 and st["lastChecked"] > 0, st
            assert (st["pacman"]["items"], st["flatpak"]["items"], st["aur"]["items"]) == (
                ["bash", "gspell"], ["com.example.App"], ["ani-cli"]), st
            assert ipc("pill", "open").returncode == 0
            wait_pill(lambda v: v["updateBadge"] == "\uf0ed 4", "update badge in the bar")
            assert ipc("pill", "updates").returncode == 0      # click on the badge
            up = wait_pill(lambda v: v["surface"] == "updates" and v["tierH"] == v["tierTarget"] > 0, "updates surface")
            assert up["tierW"] == 400, up
            assert ipc("pill", "close").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "closed")
            calls = set((home / "update-calls").read_text().splitlines())
            assert calls == {"checkupdates ", "flatpak remote-ls --updates --columns=application", "paru -Qua"}, calls

            # ---- 6.2 network and bluetooth surfaces (no NetworkManager or BlueZ here, so their
            # empty states); in frame mode the System view's Wi-Fi/Bluetooth tiles open them ----
            for name in ("network", "bluetooth"):
                assert ipc("pill", name).returncode == 0
                sv = wait_pill(lambda v: v["surface"] == name and v["tierH"] == v["tierTarget"] > 0, name + " surface")
                assert sv["tierW"] == 400, sv
                if name == "network":   # opening rescans: the refresh icon spins, then stops
                    assert sv["wifiSpinning"] is True, sv
                    wait_pill(lambda v: v["wifiSpinning"] is False, "refresh icon stops after the scan", timeout=5)
            for tile, name in (("wifiTile", "network"), ("btTile", "bluetooth")):
                assert ipc("pill", "system").returncode == 0
                sv = wait_pill(lambda v: v["surface"] == "system" and v["tierH"] == v["tierTarget"] > 100
                               and v[tile], "system surface")
                pointer(*sv[tile][:2]); time.sleep(0.2)
                subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)
                wait_pill(lambda v: v["surface"] == name, f"System {tile} opens {name}")
            assert ipc("pill", "close").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "closed")

            # Bar chips: the hover highlight's padding takes clicks too, and a click on the glyph
            # opens the surface once (a double fire would toggle it straight back closed).
            assert ipc("pill", "open").returncode == 0
            bar = wait_pill(lambda v: v["state"] == "hover" and v["w"] >= v["hoverW"] and v["volChip"],
                            "bar row (fully wide, so chip positions are final)")
            assert bar["caffeineChip"], "Caffeine is always in the expanded bar, even while off"
            cx, cy, cw = bar["volChip"]
            for x, what in ((cx, "glyph"), (cx - cw // 2 - 2, "highlight padding")):
                pointer(x, cy); time.sleep(0.2)
                subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)
                wait_pill(lambda v: v["surface"] == "sound", f"volume chip {what} opens Sound")
                time.sleep(0.4)
                assert pill()["surface"] == "sound", f"volume chip {what}: fired twice (toggled closed)"
                assert ipc("pill", "closeSurface").returncode == 0
                wait_pill(lambda v: v["surface"] == "" and v["tierH"] == 0, "sound closed")
            assert ipc("pill", "close").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "closed")

            # ---- 6.1 polkit prompt, driven by a fake AuthFlow; real keyboard and pointer ----
            def polkit_state():
                return json.loads(ipc("polkitState").stdout)

            def wait_polkit(accept, what, timeout=3):
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    v = polkit_state()
                    if accept(v):
                        return v
                    time.sleep(0.05)
                raise AssertionError(f"{what}: {polkit_state()}")

            assert polkit_state()["open"] is False
            assert ipc("polkit", "start").returncode == 0
            wait_polkit(lambda v: v["open"] and v["fieldFocus"], "prompt opens with the field focused")
            pwin = focus_at(400, 300)                      # the dimmed full-screen window
            type_text(pwin, "hunter2"); keys(pwin, "Return")
            v = wait_polkit(lambda v: v["submitted"] == ["hunter2"], "Enter submits the password")
            assert v["field"] == "" and v["error"] == "", v   # the password leaves the field at once
            assert ipc("polkit", "fail").returncode == 0     # wrong password: polkit asks again
            v = wait_polkit(lambda v: v["error"] != "", "failure shown")
            assert v["error"] == "Authentication failed, try again." and v["open"], v
            type_text(pwin, "correct"); keys(pwin, "Return")
            wait_polkit(lambda v: v["submitted"] == ["hunter2", "correct"], "retry submits again")
            assert ipc("polkit", "done").returncode == 0
            wait_polkit(lambda v: not v["open"], "closes when the request completes")
            # Two identities: a click on the other one selects it; Escape cancels.
            assert ipc("polkit", "startTwo").returncode == 0
            v = wait_polkit(lambda v: v["open"] and v["wheel"], "identity choice")
            pointer(*v["wheel"]); time.sleep(0.2)
            subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)
            wait_polkit(lambda v: v["selected"] == "wheel", "identity switched")
            pwin = focus_at(400, 300)
            type_text(pwin, "typed")
            # Real input (XTEST), not `key --window` (XSendEvent): the prompt unmaps while
            # handling the press, and a synthetic event's release is then lost, leaving a
            # phantom Escape for the next focused field (the cheatsheet filter, 6.5a).
            subprocess.run(["xdotool", "key", "Escape"], env=env, check=True, timeout=5)
            v = wait_polkit(lambda v: not v["open"], "Escape cancels")
            assert v["cancels"] == 1 and v["submitted"] == [] and v["field"] == "", v

            # ---- 6.3 devices: fake lsblk/udisksctl/thunar; real clicks on chip, Open, Eject ----
            assert ipc("pill", "open").returncode == 0
            v = wait_pill(lambda v: v["state"] == "hover" and v["w"] >= v["hoverW"] and v["devChip"],
                          "USB chip while a stick is in (bar fully wide)")
            pointer(*v["devChip"][:2]); time.sleep(0.2)
            subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)
            v = wait_pill(lambda v: v["surface"] == "devices" and v["tierH"] == v["tierTarget"] > 0
                          and v["openBtn"] and v["ejectBtn"], "devices surface from the chip")
            assert v["tierW"] == 400, v
            pointer(*v["openBtn"][:2]); time.sleep(0.2)                 # mounted: straight to thunar
            subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)
            wait_file(home / "thunar-calls", b"/run/media/suraj/STICK\n")
            wait_pill(lambda v: v["surface"] == "", "Open closes the surface")
            assert ipc("pill", "devices").returncode == 0
            v = wait_pill(lambda v: v["surface"] == "devices" and v["tierH"] == v["tierTarget"] > 0
                          and v["ejectBtn"], "devices surface again")
            pointer(*v["ejectBtn"][:2]); time.sleep(0.2)                # unmount, then power off
            subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)
            wait_file(home / "udisks-calls", b"unmount -b /dev/sdb1\npower-off -b /dev/sdb\n")
            wait_pill(lambda v: v["devChip"] is None and v["ejectBtn"] is None, "stick gone: chip and card go")
            assert ipc("pill", "close").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "closed")

            # ---- 6.5a settings: real clicks write settings.json through Config.set ----
            def click_at(path, what):
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    xy = json.loads(ipc("where", path).stdout or "null")
                    if xy:
                        break
                    time.sleep(0.05)
                assert xy, f"{what}: {path} not shown"
                pointer(*xy); time.sleep(0.15)
                subprocess.run(["xdotool", "click", "1"], env=env, check=True, timeout=5)

            def wait_settings(accept, what, timeout=3):
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    data = json.loads(settings.read_text())
                    if accept(data):
                        return data
                    time.sleep(0.05)
                raise AssertionError(f"{what}: {settings.read_text()}")

            configure({"appearance": {"layout": "frame"}, "custom": {"keep": [1, 2]}},
                      lambda v: v["pills"] and v["pills"][0]["animate"], "settings baseline")
            assert ipc("pill", "system").returncode == 0     # frame mode: System links to Settings
            wait_pill(lambda v: v["surface"] == "system" and v["tierH"] == v["tierTarget"] > 100, "system")
            click_at("allSettings", "System's All settings link")
            sv = wait_pill(lambda v: v["surface"] == "settings" and v["tierH"] == v["tierTarget"] > 0, "settings surface")
            assert sv["tierW"] == min(920, sv["hoverW"] - 76) and sv["tierH"] == min(560, sv["winH"] - 116), sv
            click_at("restStyle/choice:Handle", "rest style")
            wait_settings(lambda d: d.get("pill", {}).get("restStyle") == "handle", "pill.restStyle written")
            wait_pill(lambda v: v["handle"], "pill follows the new rest style")
            click_at("animations", "animations switch")
            data = wait_settings(lambda d: d["appearance"].get("animations") is False, "animations written")
            wait_pill(lambda v: not v["animate"], "animations off")
            click_at("section:power", "Power & idle")
            click_at("lockSec/choice:5 min", "lock timeout")
            data = wait_settings(lambda d: d.get("idle", {}).get("lockSec") == 300, "idle.lockSec written")
            click_at("suspendSec/choice:1 h", "suspend timeout")
            data = wait_settings(lambda d: d["idle"].get("suspendSec") == 3600, "idle.suspendSec written")
            click_at("section:night", "Night light")
            click_at("temperature/choice:3500 K", "temperature")
            wait_settings(lambda d: d.get("nightLight", {}).get("temperature") == 3500, "temperature written")
            click_at("from/plus", "from +30 min")
            data = wait_settings(lambda d: d["nightLight"].get("from") == "20:00", "nightLight.from written")
            assert data["custom"] == {"keep": [1, 2]} and data["appearance"]["layout"] == "frame", data   # rest kept
            settings.write_text('{"appearance": {"layout": "frame"},')        # a half-saved hand edit
            time.sleep(0.5)
            click_at("temperature/choice:4500 K", "temperature on a malformed file")
            time.sleep(0.5)
            assert settings.read_text() == '{"appearance": {"layout": "frame"},', "Config.set overwrote a malformed file"
            click_at("section:about", "About")
            click_at("section:keybinds", "Keybinds")
            click_at("openCheatsheet", "Open cheatsheet")
            wait_pill(lambda v: v["surface"] == "cheatsheet", "Settings' Keybinds opens the cheatsheet")
            assert ipc("pill", "close").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "closed")

            # ---- 6.5b settings: displays, sound, network/bluetooth links, default apps, gaming ----
            configure({"appearance": {"layout": "frame"}, "custom": {"keep": [1, 2]}},
                      lambda v: v["pills"] and v["pills"][0]["animate"], "6.5b baseline")
            assert ipc("pill", "settings").returncode == 0
            wait_pill(lambda v: v["surface"] == "settings" and v["tierH"] == v["tierTarget"] > 0, "settings surface")
            # Displays: both monitors parsed from the fake `hyprctl monitors -j`, sorted by x.
            click_at("section:displays", "Displays")
            wait_state(lambda v: v["pills"][0]["monitors"] ==
                       ["HDMI-A-1 1920x1080 @ 75 Hz", "DP-2 3440x1440 @ 165 Hz"], "both monitors listed, sorted")
            # Sound: no PipeWire in the sandbox, so the empty state; the link opens the sound surface.
            click_at("section:sound", "Sound")
            click_at("openSound", "Volume and apps link")
            wait_pill(lambda v: v["surface"] == "sound", "settings' sound link opens the sound surface")
            assert ipc("pill", "settings").returncode == 0
            wait_pill(lambda v: v["surface"] == "settings" and v["tierH"] == v["tierTarget"], "back to settings, settled")
            # Network & Bluetooth links open their surfaces.
            click_at("section:connections", "Network & Bluetooth")
            click_at("openNetwork", "Wi-Fi Open")
            wait_pill(lambda v: v["surface"] == "network", "network surface")
            assert ipc("pill", "settings").returncode == 0
            wait_pill(lambda v: v["surface"] == "settings" and v["tierH"] == v["tierTarget"], "back to settings, settled")
            click_at("section:connections", "Network & Bluetooth")
            click_at("openBluetooth", "Bluetooth Open")
            wait_pill(lambda v: v["surface"] == "bluetooth", "bluetooth surface")
            assert ipc("pill", "settings").returncode == 0
            wait_pill(lambda v: v["surface"] == "settings" and v["tierH"] == v["tierTarget"], "back to settings, settled")
            # Default apps: pick a candidate and confirm the exact xdg-mime command + the new row.
            click_at("section:defaults", "Default apps")
            click_at("default:browser", "browser chooser")
            click_at("candidate:zyxtest.desktop", "Zyxtest Launcher candidate")
            wait_file(home / "xdg-mime-calls",
                      b"default zyxtest.desktop x-scheme-handler/https x-scheme-handler/http text/html application/xhtml+xml\n")
            wait_state(lambda v: "browser=zyxtest.desktop" in v["pills"][0]["defaults"], "browser re-queried to the chosen app")
            # Gaming: the switch writes gaming.autoGameMode and unknown keys are kept.
            click_at("section:gaming", "Gaming")
            click_at("autoGameMode", "Game Mode follows games switch")
            data = wait_settings(lambda d: d.get("gaming", {}).get("autoGameMode") is False, "gaming.autoGameMode written")
            assert data["custom"] == {"keep": [1, 2]} and data["appearance"]["layout"] == "frame", data
            click_at("autoGameMode", "switch again")
            wait_settings(lambda d: d.get("gaming", {}).get("autoGameMode") is True, "gaming.autoGameMode restored")
            assert ipc("pill", "close").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "closed")

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

            log.flush()
            # ---- Media players: a second run on a private bus with fake Spotify + Firefox ----
            # (no service activation: scripts/tests/private-bus.conf; the main run has no bus)
            shell.terminate(); shell.wait(timeout=5)
            settings.write_text(json.dumps({"appearance": {"layout": "frame"}}))   # reset for the second run
            for name, colour in (("spotify", "#1db954"), ("youtube", "#ff4e45")):
                subprocess.run(["magick", "-size", "64x64", "xc:" + colour, str(home / f"{name}.png")], check=True)
            fake = ROOT / "scripts/tests/fake_mpris.py"
            mlog = (home / "mpris-shell.log").open("w+")
            script = (f'python3 -W ignore "{fake}" 0 "{home}/spotify.png" & '
                      f'python3 -W ignore "{fake}" 1 "{home}/youtube.png" & sleep 1; '
                      f'exec qs --no-color --path "{fixture}"')
            benv = {k: v for k, v in env.items() if k != "DBUS_SESSION_BUS_ADDRESS"}
            shell = subprocess.Popen(["dbus-run-session", f"--config-file={ROOT}/scripts/tests/private-bus.conf",
                                      "--", "sh", "-c", script], cwd=ROOT, env=benv, stdout=mlog, stderr=mlog,
                                     start_new_session=True)   # own group: the fake players die with it
            shell.group = True
            try:
                wait_state(lambda v: v["pills"] and v["pills"][0]["state"] == "rest", "shell on the private bus")
            except AssertionError:
                mlog.flush(); print((home / "mpris-shell.log").read_text()[-3000:]); raise
            assert ipc("pill", "open").returncode == 0
            bar = wait_pill(lambda v: v["w"] == 696 and v["clock"] is not None, "clock shown")
            ck = bar["clock"]
            assert abs((ck[0] + ck[1]) / 2 - bar["w"] / 2) <= 1 and ":" in ck[2], ck   # clock at the true centre
            assert not [s for s in bar["rowItems"] if s[0] < ck[1] and s[1] > ck[0]], (ck, bar["rowItems"])
            assert ipc("pill", "dashboard").returncode == 0
            d = wait_pill(lambda v: v["dashMain"] == "Spotify" and v["dashOthers"] == ["Mozilla Firefox"],
                          "Spotify main (even paused), Firefox listed")
            assert ipc("dashChoose", "0").returncode == 0
            wait_pill(lambda v: v["dashMain"] == "Mozilla Firefox" and v["dashOthers"] == ["Spotify"], "chosen player")
            assert ipc("pill", "close").returncode == 0
            wait_pill(lambda v: v["state"] == "rest", "closed")
            assert ipc("pill", "dashboard").returncode == 0
            wait_pill(lambda v: v["dashMain"] == "Spotify", "reopening starts with Spotify again")
            mlog.flush()
            (home / "shell.log").write_text((home / "shell.log").read_text() + (home / "mpris-shell.log").read_text())
            print("PASS: media players (private bus, fake Spotify + Firefox): Spotify main even paused, others listed,")
            print("      choosing and reset on reopen; centred bar clock clear of the row")

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
            print("PASS: settings read at startup, fixed reserves, empty masks, per-monitor fullscreen and hotplug")
            print("PASS: rest-style override/reset, invalid settings, frame pixels on private Xvfb")
            print("PASS: pill rest geometry and shape pixels, edge dwell/pass-through, collapse, IPC pin/toggle,")
            print("      frame band counts as the pill, fullscreen hide + peek (hides untouched after 800 ms),")
            print("      rest-only click-to-expand (tab, and handle: margin + screen edge, not the whole edge),")
            print("      collapse-delay setting, animations off (real pointer on Xvfb)")
            print("PASS: surfaces: open/switch/re-open toggle, Escape, stays open, badge clears on Notifications only,")
            print("      fullscreen closes them, tier over its chip, tier shape pixels (rounded corners, concave joins)")
            print("PASS: dashboard: bar widens before the tier rises, 920x420 clamped, clock/media tabs, toggle, switch")
            print("PASS: edge drawers: toasts grow from the top-right corner (392 px, max 4, timeout, dismiss")
            print("      closes it, shape pixels), OSD 52x220 from the right edge (pixels, hides after 2 s, mic),")
            print("      both hide on fullscreen")
            print("PASS: launcher (5.1) by keyboard: 640x470 clamped, app search + launch, calculator (qalc -t, copy),")
            print("      actions (destructive need two Enters within 3 s, run after closing), clipboard (list,")
            print("      image thumbnail, Delete, filter, copy), Super+V switch/toggle, Escape")
            print("PASS: cheatsheet (5.2): hyprctl binds -j grouped by prefix, 920x520 clamped, filter by")
            print("      keyboard, Escape, reopens unfiltered, Super+/ toggles")
            print("PASS: updates (6.4): checkupdates + flatpak + paru -Qua counted, badge in the bar, surface;")
            print("      only those three read-only commands ever ran")
            print("PASS: network/bluetooth (6.2): both surfaces open at 400 px; real clicks on the System")
            print("      view's Wi-Fi and Bluetooth tiles open them in frame mode; refresh spins, then stops")
            print("PASS: bar chips: a click on the glyph opens its surface once; the hover highlight's")
            print("      padding takes clicks too (real pointer); Caffeine always in the bar")
            print("PASS: polkit prompt (6.1, fake AuthFlow): overlay with exclusive keyboard, field focused,")
            print("      Enter submits and clears, failure shown and retried, identity choice, Escape cancels")
            print("PASS: devices (6.3, fake lsblk/udisksctl): USB chip only while a stick is in, surface from")
            print("      it, Open goes to thunar, Eject unmounts then powers off; chip goes with the stick")
            print("PASS: settings (6.5a): opened from System's link, 920x560 clamped; real clicks on rest")
            print("      style, animations, lock/suspend timeouts, temperature and the from stepper write")
            print("      settings.json (unknown keys kept) and take effect; a malformed file is never overwritten")
            print("PASS: settings (6.5b): displays (both monitors, sorted, read-only), sound empty state + link,")
            print("      network/bluetooth links, default apps (the exact xdg-mime default command, the row")
            print("      re-queried), Game Mode auto toggle written to settings.json (unknown keys kept)")
            print("PASS: layers, per-surface namespaces, keyboard focus only for an open surface (static; Xvfb has no layer shell)")
            print("NOT TESTED: live Wayland exclusive zones, click-through, direct scanout or VRR")
        except Exception:
            log.flush()
            print((home / "xvfb.log").read_text()[-2000:])
            print((home / "shell.log").read_text()[-6000:])
            raise
        finally:
            try:
                if shell is not None:
                    if getattr(shell, "group", False):
                        try:
                            os.killpg(shell.pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                    else:
                        shell.terminate()
                    try:
                        shell.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        shell.kill()
                        shell.wait()
            finally:
                display.stdin.close()
                try:
                    display.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(display.pid, signal.SIGKILL)
                    display.wait()
                finally:
                    display.stdout.close()
                assert all(p.exists() and p.lstat().st_ino == inode for p, inode in sockets.items()), \
                    "Private Xvfb changed an existing X11 socket"
                assert display.returncode == 0, "xvfb-run failed to shut down cleanly"
