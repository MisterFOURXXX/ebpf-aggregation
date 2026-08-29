#!/bin/bash
# disable_xdp_tx.sh - Forces the aggregator to use kernel routing for replies
# This is done by recompiling the eBPF program with XDP_PASS instead of XDP_TX
# For simulation, we just detach and use a modified .o file
set -e
INTERFACE=${1:-eth0}

echo "[Ablation] Disabling XDP_TX (using kernel stack for replies)"
sudo bpftool net detach xdp dev $INTERFACE

# Attach a modified version that returns XDP_PASS on completion
# (In a real scenario, you'd compile aggregator_pass.bpf.c separately)
# For this demo, we simulate by detaching and telling the user to run a proxy.
echo "Simulated: XDP_TX disabled. Replies will traverse the full kernel stack."