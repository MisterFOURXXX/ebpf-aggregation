#!/bin/bash
# disable_xdp_tx.sh - Simulates disabling XDP_TX by detaching and using a stub
set -e
INTERFACE=${1:-eth0}
echo "[Ablation] Disabling XDP_TX (using kernel stack for replies)"
sudo ip link set dev $INTERFACE xdp off
echo "Simulated: XDP_TX disabled. Replies will traverse the full kernel stack."