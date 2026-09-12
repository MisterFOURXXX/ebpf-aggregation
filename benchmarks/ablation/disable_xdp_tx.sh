#!/bin/bash
# ============================================================
# disable_xdp_tx.sh
# Ablation A3 helper: replace XDP_TX-based aggregator with the
# XDP_PASS variant. This forces replies to go through the kernel
# network stack, isolating the cost of the XDP_TX fast-path.
# ============================================================
set -e

INTERFACE=${1:-lo}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "[A3] Interface: $INTERFACE"
echo "[A3] Root:      $ROOT"

# 1. Detach any existing XDP program from the interface
echo "[A3] Detaching existing XDP program (if any)..."
sudo bpftool net detach xdp dev "$INTERFACE" 2>/dev/null || true
sudo rm -f /sys/fs/bpf/xdp_aggregator 2>/dev/null || true
sudo rm -f /sys/fs/bpf/xdp_aggregator_pass 2>/dev/null || true

# 2. Check that the XDP_PASS variant exists
if [ ! -f "$ROOT/ebpf/aggregator_pass.bpf.o" ]; then
    echo "[A3] ERROR: ebpf/aggregator_pass.bpf.o not found."
    echo "[A3] Build it with: cd ebpf && make"
    exit 1
fi

# 3. Load the XDP_PASS variant
echo "[A3] Loading XDP_PASS aggregator..."
sudo bpftool prog load "$ROOT/ebpf/aggregator_pass.bpf.o" \
    /sys/fs/bpf/xdp_aggregator_pass type xdp

# 4. Attach to the interface
echo "[A3] Attaching to $INTERFACE..."
sudo bpftool net attach xdp pinned /sys/fs/bpf/xdp_aggregator_pass dev "$INTERFACE"

# 5. Show current state
echo "[A3] Current XDP programs on $INTERFACE:"
sudo bpftool net list | grep -A 5 "xdp:" || true

echo ""
echo "[A3] Done. XDP_TX is now DISABLED for this test."
echo "[A3] To restore normal operation:"
echo "     sudo bpftool net detach xdp dev $INTERFACE"
echo "     sudo rm -f /sys/fs/bpf/xdp_aggregator_pass"