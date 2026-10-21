#!/usr/bin/env bash
# Synthetic tests for bbe-rdp: fake HOME, fake FreeRDP client, sentinel token.
# Never touches real downloads, sessions or Hyprland. Run: ./bbe-rdp.test.sh
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/bbe-rdp"
SENTINEL="PAAAuthCookie=btav2_SENTINEL_TOKEN_DO_NOT_LEAK"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

mkdir -p "$T/home/Downloads" "$T/home/.local/opt/freerdp-bbe/bin" "$T/bin" "$T/tmp" "$T/elsewhere"
# Fake client: records args, the .rdp it was given and its limits; then behaves per env.
cat > "$T/bin/sdl-freerdp3" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$T/args"
cp -- "$1" "$T/given.rdp"
echo "core=$(ulimit -c) umask=$(umask) ecam=${FREERDP_ECAM_MAX_HEIGHT:-unset}" > "$T/limits"
[[ -n "${FAKE_OUTPUT:-}" ]] && echo "$FAKE_OUTPUT"
[[ -n "${FAKE_SLEEP:-}" ]] && sleep "$FAKE_SLEEP"
exit "${FAKE_EXIT:-0}"
EOF
chmod +x "$T/bin/sdl-freerdp3"
cp "$T/bin/sdl-freerdp3" "$T/home/.local/opt/freerdp-bbe/bin/sdl-freerdp3"
cp "$T/bin/sdl-freerdp3" "$T/bin/xfreerdp3"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/hyprctl"
chmod +x "$T/bin/hyprctl"

fixture() { # $1 = path; portal file with cameras on and the sentinel token
  printf 'full address:s:192.0.2.1\nscreen mode id:i:2\nsmart sizing:i:1\ncamerastoredirect:s:*\ngatewayaccesstoken:s:%s\n' "$SENTINEL" > "$1"
}
run() { # run bbe-rdp in the sandbox; output to $T/out
  env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" TMPDIR="$T/tmp" T="$T" \
    FAKE_EXIT="${FAKE_EXIT:-0}" FAKE_OUTPUT="${FAKE_OUTPUT:-}" FAKE_SLEEP="${FAKE_SLEEP:-}" \
    bash "$SCRIPT" "$@" > "$T/out" 2>&1
}
DL="$T/home/Downloads"
LOGS="$T/home/.local/state/bbe-rdp"

# 1. Fresh download, defaults
fixture "$DL/launch (1).rdp"
FAKE_EXIT=3 run && rc=0 || rc=$?
check "client exit status preserved" '[[ $rc -eq 3 ]]'
check "download deleted after copy" '[[ ! -e "$DL/launch (1).rdp" ]]'
check "client still received the token" 'grep -qF "$SENTINEL" "$T/given.rdp"'
check "portal camera preference kept" 'grep -qx "camerastoredirect:s:\*" "$T/given.rdp"'
check "windowed + smart sizing off" 'grep -qx "screen mode id:i:1" "$T/given.rdp" && grep -qx "smart sizing:i:0" "$T/given.rdp"'
check "reconnect capped at 6 (SDL)" 'grep -qx "+auto-reconnect" "$T/args" && grep -qx "/auto-reconnect-max-retries:6" "$T/args"'
check "no persistent bitmap cache" '! grep -q "persist" "$T/args"'
check "core dumps off, umask 077" 'grep -qx "core=0 umask=0077 ecam=720" "$T/limits"'
check "temp copy cleaned up" '[[ -z "$(ls -A "$T/tmp")" ]]'
check "no fresh-file staleness warning" '! grep -q "Warning:" "$T/out"'
check "log dir 700, log 600" '[[ $(stat -c %a "$LOGS") == 700 && $(stat -c %a "$LOGS"/*.log) == 600 ]]'
check "token never in output or log" '! grep -rqF "SENTINEL" "$T/out" "$LOGS"'

# 2. Stale file, --keep, --no-camera, gateway rejection hint
fixture "$DL/launch.rdp"; touch -d '5 minutes ago' "$DL/launch.rdp"
FAKE_EXIT=1 FAKE_OUTPUT="ERROR rdg_process_tunnel_authorization_response: RPC_S_ACCESS_DENIED" run --keep --no-camera || true
check "stale warning" 'grep -q "s old; its gateway token" "$T/out"'
check "--keep preserves download" '[[ -f "$DL/launch.rdp" ]]'
check "--no-camera clears cameras" 'grep -qx "camerastoredirect:s:" "$T/given.rdp"'
check "gateway rejection hint" 'grep -q "Click Connect in the BBE portal again" "$T/out"'
rm -f "$DL/launch.rdp"

# 3. Never delete a symlink (or its target) or a file outside ~/Downloads
fixture "$T/elsewhere/real.rdp"; ln -s "$T/elsewhere/real.rdp" "$DL/launch.rdp"
run || true
check "symlink in Downloads not deleted" '[[ -L "$DL/launch.rdp" && -f "$T/elsewhere/real.rdp" ]]'
rm -f "$DL/launch.rdp"
run --file "$T/elsewhere/real.rdp" || true
check "--file outside Downloads not deleted" '[[ -f "$T/elsewhere/real.rdp" ]]'

# 4. X11 path uses its own retry budget
fixture "$DL/launch.rdp"
run --single || true
check "reconnect capped at 10 (xfreerdp3)" 'grep -qx "/auto-reconnect-max-retries:10" "$T/args"'

# 5. Ctrl+C (SIGINT to the process group) still removes the temp copy
fixture "$DL/launch.rdp"; rm -f "$T/limits"
setsid bash -c 'exec "$@"' _ env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" TMPDIR="$T/tmp" T="$T" FAKE_SLEEP=5 bash "$SCRIPT" > "$T/out" 2>&1 &
pid=$!
for _ in $(seq 50); do [[ -f "$T/limits" && -n "$(ls -A "$T/tmp")" ]] && break; sleep 0.1; done
sleep 0.7 # let the socket sampler take a few samples
kill -INT -- "-$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
check "temp copy removed after SIGINT" '[[ -z "$(ls -A "$T/tmp")" ]]'

# 6. Socket sampler runs alongside the client and stops with it
netf=$(ls -t "$LOGS"/*.net | head -1)
s1=$(stat -c %s "$netf"); sleep 0.7; s2=$(stat -c %s "$netf")
check "socket sampler wrote samples" 'grep -qE "net: sockets=[0-9]+ rx=[0-9]+ rq=" "$netf"'
check "socket sampler stopped with the client" '[[ $s1 -eq $s2 ]]'

# 7. --stalls verdicts on a synthetic 20s session: one stall per failure mode
awk 'BEGIN { rx = 0; rt = 0
  for (t = 0; t <= 20000; t += 250) {
    rx += (t > 12500 && t <= 14000) ? 10000 : 100           # data burst for stall 4
    if (t > 4500 && t <= 6000) rt++                          # retransmits for stall 2
    rq = (t > 8500 && t <= 10000) ? 100000 : 0               # unread data for stall 3
    s = (t > 19000) ? 0 : 1                                  # disconnected for stall 6
    printf "[10:00:%02d:%03d] net: sockets=%d rx=%d rq=%d sq=0 retrans=%d rtt=20.0 lastrcv=50\n", t / 1000, t % 1000, s, rx, rq, rt } }' > "$LOGS/synthetic.net"
pfx='[1:1] [INFO][com.freerdp.channels.rdpgfx.client] - [x]: stall:'
{ echo "# Launching BBE RDP: synthetic"
  for t in 02 06 10 14; do echo "[10:00:$t:000] $pfx input input_wait_ms=1500 no_frame_ms=1600 unacked=0"; done
  echo "[10:00:18:000] $pfx frame frame_ms=2000 decode_ms=1500.0 endframe_ms=10 wait_ms=490 bytes=1 commands=1 unacked=1"
  echo "[10:00:20:000] $pfx input input_wait_ms=1000 no_frame_ms=1000 unacked=0"; } > "$LOGS/synthetic.log"
run --stalls "$LOGS/synthetic.log" || true
verdicts=$(grep -o -- '-> [A-Z]*' "$T/out" | cut -c4- | tr '\n' ' ')
check "--stalls verdicts per failure mode" '[[ "$verdicts" == "REMOTE NETWORK LOCAL DATA LOCAL DISCONNECTED " ]]'
check "--stalls totals" 'grep -q "6 stalls, 9.0 s total" "$T/out"'
[[ "$verdicts" == "REMOTE NETWORK LOCAL DATA LOCAL DISCONNECTED " ]] || cat "$T/out"

echo; [[ $fails -eq 0 ]] && echo "PASS: all checks" || { echo "$fails check(s) failed"; exit 1; }
