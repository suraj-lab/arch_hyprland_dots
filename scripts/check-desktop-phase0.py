#!/usr/bin/env python3
"""Repository-only Phase 0 checks. No live shell, compositor or service commands."""
import ast
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = "362b952"  # reviewed pre-Phase-0 baseline; this gate intentionally targets Phase 0
QT = Path("/usr/lib/qt6/bin")  # /usr/bin/qmllint may be Qt 5 on Arch
os.chdir(ROOT)
ENV = dict(os.environ, LC_ALL="C.UTF-8", QML_DISABLE_DISK_CACHE="1",
           QT_LOGGING_RULES="*.warning=true;*.critical=true", QT_FORCE_STDERR_LOGGING="1")


def run(*command, env=ENV):
    result = subprocess.run(command, capture_output=True, text=True, env=env, timeout=60)
    if result.returncode:
        print(result.stdout + result.stderr, end="")
        result.check_returncode()
    return result.stdout


frozen = ["deploy/gaming", ".config/environment.d/99-gaming-session.conf", ".config/gamescope",
          "scripts/install-gaming-mode.sh", "docs/gaming-mode.md",
          "packages/gaming-mode.txt", "packages/daily-apps.txt"]
run("git", "diff", "--exit-code", BASE, "--", *frozen)
assert not run("git", "ls-files", "--others", "--exclude-standard", "--", *frozen).strip(), "new frozen files"
# Only the Gaming Mode restore line of autostart.lua is frozen (SPEC "Don't touch Gaming Mode").
restore = '\thl.exec_cmd("/usr/local/bin/gaming-desktop-restore")\n'
assert restore in Path(".config/hypr/modules/autostart.lua").read_text(), "gaming-desktop-restore line changed"
binds = ".config/hypr/modules/binds.lua"
# Existing binds keep their exact text; new binds may only be appended after this marker
# (SPEC §4.2 lists the allowed ones: double-tap Super, Super+D, Super+slash).
NEW_BINDS = "\n-- New binds added by the DE upgrade (SPEC §4.2)"
current = Path(binds).read_text()
old, _, added = current.partition(NEW_BINDS)
# The one sanctioned command change: Super+V's wofi picker becomes the launcher's
# clipboard mode (SPEC §5.1); the key itself stays.
WOFI_CLIPBOARD = "killall wofi || cliphist list | wofi --dmenu | cliphist decode | wl-copy"
expected = run("git", "show", f"{BASE}:{binds}").replace("qs msg ", "qs ipc call ")
assert expected.count(WOFI_CLIPBOARD) == 1, "base Super+V bind not found"
assert old == expected.replace(WOFI_CLIPBOARD, "qs ipc call launcher clipboard"), "keybind semantics changed"
added_keys = re.findall(r'hl\.bind\("([^"]+)"', added)
assert set(added_keys) <= {"SUPER + SUPER_L", "SUPER + D", "SUPER + slash"}, f"unlisted new binds: {added_keys}"
for directory in [Path(".config/hypr"), Path(".config/quickshell")]:
    for file in directory.rglob("*"):
        if file.is_file() and file.suffix in (".qml", ".lua", ".sh"):
            assert not re.search(r"\bqs\s+msg\b", file.read_text()), f"old IPC: {file}"
run("git", "diff", "--check")
print("PASS: frozen paths, exact keybind migration, no obsolete IPC, whitespace")

for file in Path(".config/hypr").rglob("*.lua"):
    run("luac", "-p", str(file))
for file in Path(".config/quickshell/scripts").glob("*.sh"):
    run("bash", "-n", str(file))
for file in [*Path(".config/quickshell/scripts").glob("*.py"), Path(__file__),
             Path("scripts/tests/test_desktop_gamemode.py")]:
    ast.parse(file.read_text(), filename=str(file))
qml = list(Path(".config/quickshell").rglob("*.qml"))
for file in qml:
    run(str(QT / "qmlformat"), str(file))  # parse only; no --inplace, no formatting changes
print(f"PASS: Lua/Bash/Python syntax and Qt 6 parsing ({len(qml)} QML files)")
print(run("python3", "scripts/tests/test_desktop_gamemode.py").strip())
print(run("node", "scripts/tests/test_desktop_controller.js").strip())

# Only the toast component runs, offscreen, without access to the session bus.
with tempfile.TemporaryDirectory(prefix="qt-check-", dir=ROOT / "scripts/tests") as tmp:
    env = dict(ENV, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               XDG_RUNTIME_DIR=tmp, XDG_CACHE_HOME=tmp,
               DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent")
    output = run(str(QT / "qmltestrunner"), "-input", "scripts/tests/tst_notification_toasts.qml", env=env)
    print(next(line for line in output.splitlines() if line.startswith("Totals:")))
print("PASS: offline Phase 0 checks. Full QML lint and supervised live smoke tests remain separate gates.")
