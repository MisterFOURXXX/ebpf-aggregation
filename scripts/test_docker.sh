#!/bin/bash
cd "$(dirname "$0")/.."
IMG=ebpf-p4-agg:latest

echo "=== Docker Test ==="

echo "[1/2] Build image..."
sudo docker build -t $IMG . > /dev/null 2>&1

echo "[2/2] Run integration test..."
sudo docker run --rm --privileged --network host $IMG \
    bash -c "cd /app && \
             pkill -f userspace_aggregator 2>/dev/null; \
             python3 benchmarks/ablation/userspace_aggregator_silent.py & \
             sleep 2; \
             cd examples/build && timeout 20 ./simple_allreduce 127.0.0.1 9999 0; \
             pkill -f userspace_aggregator"

echo "=== Done ==="
