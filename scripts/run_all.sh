#!/bin/bash
# ============================================================
#  MASTER SCRIPT — Runs every experiment end-to-end
# ============================================================
cd "$(dirname "$0")/.."

echo "=============================================="
echo "  MASTER: eBPF-P4 Aggregation Experiments"
echo "=============================================="

echo ""
echo "### 1/5: Clean (build + docker) ###"
./scripts/clean_all.sh
./scripts/clean_docker.sh

echo ""
echo "### 2/5: Build everything ###"
./scripts/build_all.sh

echo ""
echo "### 3/5: Native test suite ###"
./scripts/test_all.sh

echo ""
echo "### 4/5: Docker test ###"
./scripts/test_docker.sh

echo ""
echo "### 5/5: Kubernetes test ###"
./scripts/run_k8s_test.sh

echo ""
echo "=============================================="
echo "  ALL EXPERIMENTS COMPLETE"
echo "=============================================="
echo ""
echo "Results in benchmarks/results/:"
ls -la benchmarks/results/
echo ""
echo "Plots in benchmarks/analysis/:"
ls -la benchmarks/analysis/*.png 2>/dev/null || echo "  (no plots)"
