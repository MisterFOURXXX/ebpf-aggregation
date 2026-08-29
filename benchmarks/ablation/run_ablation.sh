#!/bin/bash
# run_ablation.sh - Disable features to prove why eBPF works

set -e
cd "$(dirname "$0")"

echo "=== Ablation Study: eBPF-Agg ==="

# Baseline: Full eBPF
echo "[1/4] Baseline (Full eBPF + XDP_TX)"
sudo bpftool net attach xdp obj ../../ebpf/aggregator.bpf.o sec xdp dev eth0
../../build/benchmarks/latency_benchmark 192.168.1.100 9999 0 1024 1000 > ../results/baseline.log

# Ablation 1: No eBPF (Userspace aggregator)
echo "[2/4] Ablation 1: No eBPF (Userspace UDP server)"
sudo bpftool net detach xdp dev eth0
python3 userspace_aggregator.py &
sleep 2
../../build/benchmarks/latency_benchmark 192.168.1.100 9999 0 1024 1000 > ../results/no_ebpf.log
killall python3

# Ablation 2: No XDP_TX (Kernel routing)
echo "[3/4] Ablation 2: No XDP_TX (Reply goes through kernel stack)"
# Reattach a modified XDP program that returns XDP_PASS for replies
# (In practice, we recompile with a flag. Here we assume a pre-built variant)
sudo bpftool net attach xdp obj ../../ebpf/aggregator_pass.bpf.o sec xdp dev eth0
../../build/benchmarks/latency_benchmark 192.168.1.100 9999 0 1024 1000 > ../results/no_xdp_tx.log

# Ablation 3: Broken chunking (large packets)
echo "[4/4] Ablation 3: Suboptimal Chunking (16KB packets)"
# Client recompiled with MAX_FLOATS_PER_PKT=4096 (implicit via env)
MAX_FLOATS=4096 ../../build/benchmarks/latency_benchmark 192.168.1.100 9999 0 1024 1000 > ../results/bad_chunk.log

echo "All ablations complete. Run python ../analysis/plot_ablation.py to generate graphs."