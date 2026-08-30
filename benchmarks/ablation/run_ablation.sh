#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Ablation Study: eBPF-Agg ==="

# Baseline
echo "[1/4] Baseline (Full eBPF + XDP_TX)"
sudo ip link set dev eth0 xdp obj ../../ebpf/aggregator.bpf.o sec xdp
../../build/benchmarks/latency_benchmark 192.168.1.100 9999 0 1024 1000 > ../results/baseline.log

# Ablation 1: No eBPF
echo "[2/4] Ablation 1: No eBPF (Userspace UDP server)"
sudo ip link set dev eth0 xdp off
python3 userspace_aggregator.py &
sleep 2
../../build/benchmarks/latency_benchmark 192.168.1.100 9999 0 1024 1000 > ../results/no_ebpf.log
killall python3 || true

# Ablation 2: No XDP_TX (simulate by using a variant that returns XDP_PASS)
# For this, we assume you have compiled aggregator_pass.bpf.o manually
echo "[3/4] Ablation 2: No XDP_TX (Reply goes through kernel stack)"
if [ -f "../../ebpf/aggregator_pass.bpf.o" ]; then
    sudo ip link set dev eth0 xdp obj ../../ebpf/aggregator_pass.bpf.o sec xdp
else
    echo "WARNING: aggregator_pass.bpf.o not found. Skipping XDP_TX ablation."
    echo "0,0,0,0" > ../results/no_xdp_tx.log
fi
../../build/benchmarks/latency_benchmark 192.168.1.100 9999 0 1024 1000 > ../results/no_xdp_tx.log

# Ablation 3: Broken chunking
echo "[4/4] Ablation 3: Suboptimal Chunking (16KB packets)"
# Reattach normal XDP
sudo ip link set dev eth0 xdp obj ../../ebpf/aggregator.bpf.o sec xdp
MAX_FLOATS=4096 ../../build/benchmarks/latency_benchmark 192.168.1.100 9999 0 1024 1000 > ../results/bad_chunk.log

echo "All ablations complete. Run python ../analysis/plot_ablation.py to generate graphs."