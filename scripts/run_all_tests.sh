#!/bin/bash
# ============================================================
# eBPF-Aggregation Test Suite — FAST VERSION
# ============================================================
cd "$(dirname "$0")/.."
ROOT=$(pwd)
LOG="$ROOT/benchmarks/results"
mkdir -p "$LOG"

echo "=============================================="
echo "   eBPF-Aggregation Test Suite (fast)"
echo "=============================================="

echo "[1/6] Cleaning..."
./scripts/clean_all.sh > /dev/null 2>&1 || true

echo "[2/6] Building..."
make all              > /dev/null 2>&1 || { echo "  FAILED: make all"; exit 1; }
make build-examples   > /dev/null 2>&1 || { echo "  FAILED: examples"; exit 1; }
make build-benchmarks > /dev/null 2>&1 || { echo "  FAILED: benchmarks"; exit 1; }
echo "  All binaries built ✓"

echo "[3/6] Unit tests..."
(cd "$ROOT/tests" && mkdir -p build && cd build && cmake .. > /dev/null 2>&1 && make > /dev/null 2>&1 && ctest 2>&1 | tail -3)

echo "[4/6] Starting aggregator..."
pkill -f userspace_aggregator 2>/dev/null || true
sleep 1
python3 benchmarks/ablation/userspace_aggregator_silent.py > /dev/null 2>&1 &
AGG_PID=$!
sleep 2
kill -0 $AGG_PID 2>/dev/null || { echo "  Aggregator failed"; exit 1; }
echo "  PID: $AGG_PID"

echo "[5/6] Running tests (short timeouts)..."
echo "--- Example (30s) ---"
(cd "$ROOT/examples/build" && timeout 30 ./simple_allreduce 127.0.0.1 9999 0) \
    | tee "$LOG/example.txt" || echo "  (timeout)"

echo "--- Latency (60s) ---"
(cd "$ROOT/benchmarks/build" && timeout 60 ./latency_benchmark 127.0.0.1 9999 0) \
    | tee "$LOG/latency_results.csv" || echo "  (timeout)"

echo "--- Scalability (30s) ---"
(cd "$ROOT/benchmarks/build" && timeout 30 ./scalability_benchmark 2>&1 | head -20) \
    | tee "$LOG/scalability_results.csv" || echo "  (timeout)"

echo "--- CPU (30s) ---"
(cd "$ROOT/benchmarks/build" && timeout 30 ./cpu_benchmark 127.0.0.1 9999 0) \
    | tee "$LOG/cpu_results.txt" || echo "  (timeout)"

echo "[6/6] Cleanup..."
pkill -f userspace_aggregator 2>/dev/null || true

echo ""
echo "=== DONE — results in $LOG ==="
ls -la "$LOG"
