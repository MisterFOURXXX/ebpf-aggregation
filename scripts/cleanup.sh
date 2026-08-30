#!/bin/bash
set -e
INTERFACE=${1:-eth0}
echo "[Cleanup] Detaching XDP from $INTERFACE..."
sudo ip link set dev $INTERFACE xdp off 2>/dev/null || echo "No XDP attached"
echo "[Cleanup] Removing pinned maps..."
sudo rm -rf /sys/fs/bpf/ebpf_agg 2>/dev/null || echo "No pinned maps"
echo "[Cleanup] Killing leftover processes..."
pkill -f "userspace_aggregator" 2>/dev/null || echo "No leftover aggregator"
echo "[Cleanup] Done."