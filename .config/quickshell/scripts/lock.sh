#!/usr/bin/env bash
# Lock the session and keep it guarded. hyprlock can die while locked (a monitor powering
# off: hyprlock#375, #953), which leaves Hyprland's "lockscreen app died" screen and a
# TTY-only way out. Here a new hyprlock takes over instead (misc.allow_session_lock_restore)
# and asks for the password again. Output goes to the journal: `journalctl -t hyprlock`.
# Started by the shell's idle lock and lock actions, and by hypridle (loginctl lock-session,
# before sleep). Detached from the shell, so a shell restart never takes the lock down.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/hyprlock-guard.lock"
flock -n 9 || exit 0                     # already guarded
pidof hyprlock >/dev/null && exit 0      # locked some other way (Ctrl+Alt+L)

fast=0
while :; do
    start=$SECONDS
    systemd-cat -t hyprlock hyprlock && exit 0   # 0: unlocked with the password
    rc=$?
    logger -t hyprlock-guard "hyprlock exited with $rc while locked; starting it again"
    # A crash after a longer run restarts at once: Hyprland shows its "lockscreen app died"
    # screen until a new lock takes over. Quick failures back off 1, 2, 3, 4 s (a monitor still
    # waking up), then give up.
    # ponytail: stops after 5 quick failures in a row, so a hyprlock broken at startup can't loop forever.
    if (( SECONDS - start < ${HYPRLOCK_FAST_SEC:-10} )); then
        (( ++fast >= 5 )) && exit "$rc"
    else
        fast=0
    fi
    sleep "$fast"
done
