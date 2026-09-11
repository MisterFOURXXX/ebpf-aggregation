#!/bin/bash
cd "$(dirname "$0")/.."
ROOT=$(pwd)
LOG="$ROOT/benchmarks/results"
mkdir -p "$LOG"

echo "=============================================="
echo "   Full Native Test Suite"
echo "=============================================="

# --- 1. Clean + Build ---
echo "[1/5] Clean..."
./scripts/clean_all.sh > /dev/null 2>&1 || true

echo "[2/5] Build..."
./scripts/build_all.sh > /dev/null 2>&1 || { echo "Build FAILED"; exit 1; }
echo "  binaries ✓"
mkdir -p "$LOG"

# --- 2. Unit tests ---
echo "[3/5] Unit tests..."
(cd "$ROOT/tests/build" && ctest 2>&1 | tail -3)

# --- 3. Start aggregator ---
echo "[4/5] Starting aggregator..."
pkill -f userspace_aggregator 2>/dev/null || true
sleep 1
python3 benchmarks/ablation/userspace_aggregator_silent.py > /dev/null 2>&1 &
AGG_PID=$!
sleep 2
kill -0 $AGG_PID 2>/dev/null || { echo "Aggregator failed"; exit 1; }
echo "  PID: $AGG_PID"

# --- 4. Benchmarks with timeouts ---
echo "[5/5] Benchmarks..."

echo "--- Example (20s) ---"
(cd "$ROOT/examples/build" && timeout 20 ./simple_allreduce 127.0.0.1 9999 0) \
    | tee "$LOG/example.txt" || echo "  (timeout)"

echo "--- Latency (30s) ---"
(cd "$ROOT/benchmarks/build" && timeout 30 ./latency_benchmark 127.0.0.1 9999 0) \
    | tee "$LOG/latency_results.csv" || echo "  (timeout)"

echo "--- Scalability (20s) ---"
(cd "$ROOT/benchmarks/build" && timeout 20 ./scalability_benchmark) \
    | tee "$LOG/scalability_results.csv" || echo "  (timeout)"

echo "--- CPU (15s) ---"
(cd "$ROOT/benchmarks/build" && timeout 15 ./cpu_benchmark 127.0.0.1 9999 0) \
    | tee "$LOG/cpu_results.txt" || echo "  (timeout)"

# --- 5. Cleanup ---
pkill -f userspace_aggregator 2>/dev/null || true

echo ""
echo "=== Results in $LOG ==="
ls -la "$LOG"
