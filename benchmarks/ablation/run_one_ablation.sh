#!/bin/bash
# ============================================================
#  Run a single ablation configuration
#  Usage: ./run_one_ablation.sh <config_file>
# ============================================================
set +m
set +b
CONFIG="$1"
[ -z "$CONFIG" ] && { echo "Usage: $0 <config.conf>"; exit 1; }
[ ! -f "$CONFIG" ] && { echo "Config not found: $CONFIG"; exit 1; }

source "$CONFIG"

cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT="$ROOT/benchmarks/results/ablation/$ABLATION_ID"
mkdir -p "$OUT"

echo ""
echo "==== Ablation: $ABLATION_ID - $ABLATION_NAME ===="
echo "  Type:       $AGGREGATOR_TYPE"
echo "  Workers:    $NUM_WORKERS"
echo "  Pkt floats: $PKT_FLOATS"
echo "  Sizes:      $LATENCY_SIZES"
echo ""

cat > "$OUT/metadata.txt" << META
ABLATION_ID=$ABLATION_ID
ABLATION_NAME=$ABLATION_NAME
AGGREGATOR_TYPE=$AGGREGATOR_TYPE
NUM_WORKERS=$NUM_WORKERS
PKT_FLOATS=$PKT_FLOATS
LATENCY_SIZES=$LATENCY_SIZES
TIMESTAMP=$(date -Iseconds)
META

# ---------- Stop any running aggregators ----------
stop_agg() {
    pkill -TERM -f userspace_aggregator 2>/dev/null || true
    pkill -TERM -f echo_aggregator 2>/dev/null || true
    sleep 0.5
    pkill -KILL -f userspace_aggregator 2>/dev/null || true
    pkill -KILL -f echo_aggregator 2>/dev/null || true
    wait 2>/dev/null || true
}
stop_agg
sleep 1

# ---------- Start aggregator ----------
AGG_PID=""
case "$AGGREGATOR_TYPE" in
  userspace|userspace_grouped)
      NUM_WORKERS=$NUM_WORKERS \
      AGG_PORT=9999 \
      python3 "$AGGREGATOR_SCRIPT" > "$OUT/aggregator.log" 2>&1 &
      AGG_PID=$!
      disown
      ;;
  ebpf_xdp)
      sudo bpftool prog load "$ROOT/ebpf/aggregator.bpf.o" \
           /sys/fs/bpf/xdp_ablation type xdp > "$OUT/aggregator.log" 2>&1 || true
      sudo bpftool net attach xdp pinned /sys/fs/bpf/xdp_ablation dev lo \
           >> "$OUT/aggregator.log" 2>&1 || true
      ;;
  xdp_pass)
      if [ ! -f "$ROOT/ebpf/aggregator_pass.bpf.o" ]; then
          echo "  [A3 skipped] aggregator_pass.bpf.o not found"
          echo "SKIPPED" > "$OUT/skipped.txt"
          return 0 2>/dev/null || exit 0
      fi
      sudo bpftool prog load "$ROOT/ebpf/aggregator_pass.bpf.o" \
           /sys/fs/bpf/xdp_ablation_pass type xdp > "$OUT/aggregator.log" 2>&1 || true
      sudo bpftool net attach xdp pinned /sys/fs/bpf/xdp_ablation_pass dev lo \
           >> "$OUT/aggregator.log" 2>&1 || true
      ;;
  *)
      echo "Unknown AGGREGATOR_TYPE: $AGGREGATOR_TYPE"
      exit 1
      ;;
esac

sleep 2

# ---------- Run benchmarks ----------
echo "  Running latency benchmark"
(cd "$ROOT/benchmarks/build" && \
    timeout 60 ./latency_benchmark 127.0.0.1 9999 0 \
    > "$OUT/latency_results.csv" 2>&1 || true)

echo "  Running scalability benchmark"
(cd "$ROOT/benchmarks/build" && \
    timeout 30 ./scalability_benchmark 127.0.0.1 9999 2 \
    > "$OUT/scalability_results.csv" 2>&1 || true)

echo "  Running CPU benchmark"
(cd "$ROOT/benchmarks/build" && \
    timeout 20 ./cpu_benchmark 127.0.0.1 9999 0 $AGG_PID \
    > "$OUT/cpu_results.txt" 2>&1 || true)

# ---------- Stop aggregator ----------
case "$AGGREGATOR_TYPE" in
  ebpf_xdp)
      sudo bpftool net detach xdp dev lo 2>/dev/null || true
      sudo rm -f /sys/fs/bpf/xdp_ablation 2>/dev/null || true
      ;;
  xdp_pass)
      sudo bpftool net detach xdp dev lo 2>/dev/null || true
      sudo rm -f /sys/fs/bpf/xdp_ablation_pass 2>/dev/null || true
      ;;
  *)
      stop_agg
      ;;
esac

echo "  Results: $OUT"
ls "$OUT" | sed 's/^/    /'
