#!/usr/bin/env python3
"""Run the real preflight with shell fakes; never launch Steam, Hyprland or SDDM."""
import fcntl
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "deploy/gaming/usr/local/bin/switch-to-gaming"
source = SCRIPT.read_text()
# Only definitions: session switching and monitor commands are never sourced.
main_start = source.index('\nif (( $# > 1 ))')
functions = source[source.index("notify() {"):main_start]
FAKES = r'''
notify-send() { printf '%s\n' "$*" >> "$HOME/notices"; echo 42; }
timeout() { shift; "$@"; }
pgrep() {
    case "$*" in
        *-child-update-ui*) test -e "$HOME/updater" ;;
        *steamwebhelper*) test -e "$HOME/webhelper" ;;
        *steam*) test -e "$HOME/running" ;;
        *) echo "unexpected pgrep: $*" >&2; return 2 ;;
    esac
}
steam() {
    printf '%s\n' "$*" >> "$HOME/commands"
    if [[ " $* " == *" -shutdown "* ]]; then
        if [[ "$CASE" != stop_failure && ! ( "$CASE" == final_stop_failure && -f "$HOME/launched" ) ]]; then
            rm -f "$HOME/running" "$HOME/webhelper" "$HOME/updater"
        fi
        return 0
    fi
    touch "$HOME/launched"
    [[ "$STEAM_RUNTIME_LOGGER" == 0 ]] || return 2
    [[ "$CASE" == launch_failure ]] && return 1
    touch "$HOME/running"
    echo "[now] Startup - Steam Client launched"
    if [[ "$CASE" == update ]]; then
        touch "$HOME/updater"
        printf '%s\n' '[now] Verification complete' '[now] Downloading update (20 of 100 KB)...'
    elif [[ "$CASE" == ui_only ]]; then
        echo '[now] Set status message: Verification complete'
        touch "$HOME/webhelper"
    elif [[ "$CASE" != stale && "$CASE" != timeout && "$CASE" != invalid ]]; then
        echo '[now] Verification complete'
        if [[ "$CASE" == late_status ]]; then
            # Real Steam emits its asynchronous UI status AFTER verification succeeds.
            echo '[now] Set status message: Verifying installation...'
        fi
        [[ "$CASE" != no_webhelper ]] && touch "$HOME/webhelper"
    fi
}
sleep() {
    # Advance Bash's clock without waiting minutes for shutdown/timeout cases.
    SECONDS=$((SECONDS + $1))
    /bin/sleep 0.02  # allow the fake background launcher to write its fixtures
    ticks=$((ticks + 1))
    if [[ "$CASE" == update && -f "$HOME/launched" ]]; then
        case "$ticks" in
            4) echo '[now] Installing update...' >> "$HOME/.local/state/gaming-mode/steam-preflight.log" ;;
            8) printf '%s\n' '[now] Update complete, launching Steam...' '[now] Startup - Steam Client launched' '[now] Verification complete' >> "$HOME/.local/state/gaming-mode/steam-preflight.log"
               rm -f "$HOME/updater"; touch "$HOME/webhelper" ;;
        esac
    fi
    if [[ "$CASE" == cancel ]]; then kill -TERM "$$"; fi
}
ticks=0
steam_preflight
rc=$?
[[ "$rc" == 0 ]] && echo SWITCH_ALLOWED
exit "$rc"
'''


def check(case, success=False, existing=False, timeout="30", held=False, prepare_only=False):
    with tempfile.TemporaryDirectory() as directory:
        home = Path(directory)
        log = home / ".local/state/gaming-mode/steam-preflight.log"
        log.parent.mkdir(parents=True)
        log.write_text("[yesterday] Verification complete\n")
        if existing:
            (home / "running").touch()
        if case == "stale":
            (home / "webhelper").touch()
        env = dict(os.environ, HOME=directory, XDG_RUNTIME_DIR=directory,
                   XDG_STATE_HOME=str(home / ".local/state"), CASE=case,
                   GAMING_STEAM_PREFLIGHT="1", GAMING_STEAM_PREFLIGHT_TIMEOUT=timeout)
        with open(home / "gaming-preflight.lock", "w") as lock:
            if held:
                fcntl.flock(lock, fcntl.LOCK_EX)
            driver = functions + FAKES
            if prepare_only:
                # Exercise the real CLI branch, but never include the dangerous switch tail.
                driver = functions + FAKES[:FAKES.index("ticks=0")]
                driver += "ticks=0\n" + source[main_start:source.index("# Kill leftovers")]
                driver += "\necho SWITCH_ALLOWED\n"
            result = subprocess.run(["bash", "-c", driver, "test-preflight", *(["--prepare-only"] if prepare_only else [])], env=env,
                                    capture_output=True, text=True, timeout=10)
        commands = (home / "commands").read_text().splitlines() if (home / "commands").exists() else []
        notices = (home / "notices").read_text() if (home / "notices").exists() else ""
        assert (result.returncode == 0) == success, (case, result, notices)
        assert ("SWITCH_ALLOWED" in result.stdout) == (success and not prepare_only), (case, result)
        flags = "-steamos3 -steampal -steamdeck -gamepadui"
        assert all(command in (flags, flags + " -shutdown") for command in commands), commands
        if success:
            assert commands[-1] == flags + " -shutdown", commands
            assert commands.count(flags) == 1, commands
            assert not (home / "running").exists()
            assert "Closing it before the session switch" in notices
            if prepare_only:
                assert "Staying on the desktop (prepare-only)" in notices
                assert "Switching to Gaming Mode" not in notices
            assert "-r 42" in notices  # replace one progress notification
        if existing and success:
            assert commands[0] == flags + " -shutdown", commands
        if case == "update":
            assert "Downloading update (20 of 100 KB)" in notices, notices
            assert "Installing update" in notices, notices
        if held or case == "invalid":
            assert not commands, commands
        if case == "stop_failure":
            assert not (home / "launched").exists()
        print("PASS:", case)


check("cold", success=True)
check("late_status", success=True)
check("ui_only", timeout="6")
check("existing", success=True, existing=True)
check("update", success=True)
check("stale", timeout="6")
check("no_webhelper", timeout="6")
check("launch_failure")
check("timeout", timeout="6")
check("stop_failure", existing=True)
check("final_stop_failure")
check("invalid", timeout="bad")
check("concurrent", held=True)
check("cancel")
check("prepare_only", success=True, prepare_only=True)
# The channel flags must remain aligned with the installed CachyOS launcher when present.
launcher = Path("/usr/lib/steamos/steam-launcher")
if launcher.exists():
    assert 'steamargs=("-steamos3" "-steampal" "-steamdeck" "-gamepadui")' in launcher.read_text()
print("PASS: channel-aware preflight, fresh verification, progress, failure/timeout/cancel and single instance")
