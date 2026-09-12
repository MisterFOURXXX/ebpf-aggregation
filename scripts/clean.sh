#!/bin/bash
# ============================================================
# clean.sh - UNIFIED cleanup:
#   - Build artifacts (from clean_all.sh)
#   - Docker + KIND leftovers (from clean_docker.sh)
#   - Experiment results + plots (from clean_everything.sh)
# Returns the repository to a fresh source-only state.
# ============================================================
cd "$(dirname "$0")/.."
ROOT=$(pwd)

echo "[clean] Removing build artifacts..."

# --- 1. Standard make clean ---
if [ -f Makefile ]; then
    make clean > /dev/null 2>&1 || true
fi
make -C ebpf clean > /dev/null 2>&1 || true

# --- 2. Build directories ---
rm -rf client_lib/build tests/build examples/build benchmarks/build operator/bin

# --- 3. CMake caches ---
find . -name "CMakeCache.txt" -delete 2>/dev/null
find . -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null

# --- 4. Compiled binaries and objects ---
find . -name "*.o" -delete 2>/dev/null
find . -name "*.so" -delete 2>/dev/null
find . -name "*.bpf.o" -delete 2>/dev/null

# --- 5. Python caches ---
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
find . -name "*.pyc" -delete 2>/dev/null

echo "[clean] Removing experiment results..."
rm -f benchmarks/results/*.csv
rm -f benchmarks/results/*.txt
rm -f benchmarks/results/*.log
rm -f benchmarks/results/ablation/*.csv 2>/dev/null || true
rm -f benchmarks/results/ablation/*.txt 2>/dev/null || true
rm -rf benchmarks/results/ablation/_report 2>/dev/null || true

echo "[clean] Removing plot images..."
rm -f benchmarks/analysis/*.png

echo "[clean] Removing Docker and KIND leftovers..."
sudo docker stop -t 0 ebpf-test-control-plane 2>/dev/null || true
sudo docker rm -f ebpf-test-control-plane 2>/dev/null || true
sudo docker network rm kind 2>/dev/null || true
sudo kind delete cluster --name ebpf-test 2>/dev/null || true
sudo docker rmi -f ebpf-p4-agg:latest 2>/dev/null || true

echo "[clean] Removing Kubernetes temporary files..."
rm -f kubeconfig 2>/dev/null || true
sudo rm -rf /sys/fs/bpf/xdp_aggregator /sys/fs/bpf/xdp_aggregator_pass \
            /sys/fs/bpf/xdp_ablation /sys/fs/bpf/xdp_ablation_pass 2>/dev/null || true

mkdir -p benchmarks/results
echo "[clean] Done. Repository is in source-only state."
