#!/bin/bash
set -euo pipefail

# === Config ===
VM="Work"
CONNECT="qemu:///system"
IVSHMEM="/dev/shm/looking-glass"
HP_NEEDED=16384  # 16384 × 2MB = 32GB

# === Logging ===
say()  { echo "[$(date +%H:%M:%S)] $*"; }
die()  { say "ERROR: $*" >&2; exit 1; }

# === Status checks ===
vm_running() {
    virsh --connect "$CONNECT" domstate "$VM" 2>/dev/null | grep -qx 'running'
}
ivshmem_ok() {
    [ -e "$IVSHMEM" ]
}
lg_running() {
    pgrep -f "looking-glass-client" &>/dev/null
}

# === Cleanup ===
cleanup() {
    if [ -n "${LG_PID:-}" ]; then
        kill "$LG_PID" 2>/dev/null && say "Stopped Looking Glass"
        wait "$LG_PID" 2>/dev/null
    fi
    # Note: hugepages are freed by /etc/libvirt/hooks/qemu when VM releases
}
trap cleanup EXIT INT TERM

# === Hugepage helpers ===
hp_alloc() {
    local current
    current=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo 0)
    if [ "$current" -lt "$HP_NEEDED" ]; then
        say "Allocating hugepages (${HP_NEEDED} × 2MB = 32GB)..."
        echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>/dev/null || true
        say "Compacting memory..."
        echo 1 | sudo tee /proc/sys/vm/compact_memory >/dev/null 2>/dev/null || true
        sleep 2
        echo "$HP_NEEDED" | sudo tee /proc/sys/vm/nr_hugepages >/dev/null || die "Failed to allocate hugepages (need sudo)"
    else
        say "Hugepages already allocated"
    fi
}

# === Commands ===
cmd_status() {
    printf "VM:          "; vm_running  && echo "running"     || echo "stopped"
    printf "IVSHMEM:     "; ivshmem_ok  && echo "available"   || echo "not found"
    printf "LookingGlass:"; lg_running && echo "running"      || echo "not running"
}

cmd_start() {
    if ! vm_running; then
        hp_alloc
        say "Starting $VM..."
        virsh --connect "$CONNECT" start "$VM" || die "virsh start failed"
        # Poll until VM reports running
        for i in $(seq 1 30); do
            vm_running && break
            sleep 1
        done
        vm_running || die "VM did not boot within 30s"
        say "VM is running"
    else
        say "VM already running"
    fi

    if lg_running; then
        die "Looking Glass is already running"
    fi

    # Wait for IVSHMEM
    for i in $(seq 1 10); do
        ivshmem_ok && break
        sleep 1
    done
    ivshmem_ok || die "IVSHMEM not ready at $IVSHMEM"

    say "Launching Looking Glass..."
    looking-glass-client &
    LG_PID=$!
    say "Looking Glass started (PID $LG_PID)"

    # Wait for Looking Glass or Ctrl-C
    wait "$LG_PID"
    say "Looking Glass exited"
}

cmd_stop() {
    if lg_running; then
        say "Killing Looking Glass..."
        pkill -f "looking-glass-client" || true
        sleep 1
    fi
    if vm_running; then
        say "Shutting down $VM..."
        virsh --connect "$CONNECT" shutdown "$VM" || {
            say "Shutdown failed, forcing off..."
            virsh --connect "$CONNECT" destroy "$VM"
        }
        # Hugepages will be freed by /etc/libvirt/hooks/qemu on VM release
    else
        say "VM not running"
    fi
}

# === Main ===
case "${1:-start}" in
    start)  cmd_start  ;;
    stop)   cmd_stop   ;;
    status) cmd_status ;;
    *)      echo "Usage: $(basename "$0") {start|stop|status}" >&2; exit 1 ;;
esac
