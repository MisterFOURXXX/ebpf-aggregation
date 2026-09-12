#!/bin/bash
# ============================================================
# run_experiments.sh - 4 experiments + plots
# ============================================================
set +m
set +b

cd "$(dirname "$0")/.."
ROOT=$(pwd)
LOG="$ROOT/benchmarks/results"
PLOTS="$ROOT/benchmarks/analysis"
mkdir -p "$LOG" "$PLOTS"

echo "eBPF-P4 Aggregation - Experiments"
echo ""

./scripts/clean.sh > /dev/null 2>&1 || true
./scripts/build.sh > /dev/null 2>&1 || { echo "BUILD FAILED"; exit 1; }
mkdir -p "$LOG" "$PLOTS"

# Unit tests
echo "Unit tests:"
(cd "$ROOT/tests/build" && ctest 2>&1 | tail -3)
echo ""

stop_agg() {
    pkill -TERM -f userspace_aggregator_silent.py 2>/dev/null || true
    for i in 1 2 3 4 5; do
        pgrep -f userspace_aggregator_silent.py > /dev/null || return
        sleep 0.3
    done
    pkill -KILL -f userspace_aggregator_silent.py 2>/dev/null || true
    wait 2>/dev/null || true
}

start_agg() {
    local n=$1
    local logfile=$2
    NUM_WORKERS=$n python3 benchmarks/ablation/userspace_aggregator_silent.py \
        > "$logfile" 2>&1 &
    disown
    sleep 1.5
}

# Exp 1 & 2
stop_agg
sleep 1
start_agg 1 "$LOG/aggregator.log"

echo "Exp 1: simple_allreduce"
(cd "$ROOT/examples/build" && timeout 20 ./simple_allreduce 127.0.0.1 9999 0) \
    | tee "$LOG/example.txt"
echo ""

echo "Exp 2: latency vs payload size"
(cd "$ROOT/benchmarks/build" && timeout 90 ./latency_benchmark 127.0.0.1 9999 0) \
    | tee "$LOG/latency_results.csv"
stop_agg
sleep 1
echo ""

# Exp 3: scalability
echo "Exp 3: scalability (aggregator restarted for each N)"
{
    echo "num_workers,worker_id,latency_us,ok"
    for N in 1 2 4 8; do
        stop_agg
        sleep 0.5
        start_agg $N "$LOG/aggregator_N${N}.log"
        echo "  aggregator N=$N ready"
        (cd "$ROOT/benchmarks/build" && \
         timeout 30 ./scalability_benchmark 127.0.0.1 9999 $N)
        stop_agg
        sleep 0.5
    done
} | tee "$LOG/scalability_results.csv"
echo ""

# Exp 4: CPU
echo "Exp 4: aggregator CPU (isolated PID)"
stop_agg
sleep 1
NUM_WORKERS=1 python3 benchmarks/ablation/userspace_aggregator_silent.py \
    > "$LOG/aggregator.log" 2>&1 &
AGG_PID=$!
disown
sleep 1.5
echo "  aggregator PID: $AGG_PID"

(cd "$ROOT/benchmarks/build" && \
    timeout 25 ./cpu_benchmark 127.0.0.1 9999 0 $AGG_PID) \
    | tee "$LOG/cpu_results.txt"
stop_agg
echo ""

# Plots
echo "Generating plots"
python3 "$PLOTS/plot_latency.py"
python3 "$PLOTS/plot_scalability.py"
python3 "$PLOTS/plot_cpu_usage.py"
echo ""

echo "DONE"
ls -la "$LOG"
