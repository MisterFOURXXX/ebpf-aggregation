#!/bin/bash
# ============================================================
# run_one_ablation.sh
#   args: NAME TYPE WORKERS PKT_FLOATS SIZE1 [SIZE2 ...]
#
# Port cleanup strategy (in order):
#   1. fuser -k 9999/udp   — kills whatever holds the port
#   2. pkill aggregator    — fallback by process name
#   3. lsof -iUDP:9999     — last resort
# Verified with ss before proceeding.
# ============================================================
set +m
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

NAME=$1; TYPE=$2; WORKERS=$3; PKT_FLOATS=$4; shift 4
SIZES="$*"

OUT="$ROOT/benchmarks/results/ablation/$NAME"
mkdir -p "$OUT"
: > "$OUT/aggregator.log"
: > "$OUT/latency_results.csv"
: > "$OUT/scalability_results.csv"
: > "$OUT/cpu_results.txt"

printf 'Ablation: %s\n'     "$NAME"
printf '  Type:       %s\n' "$TYPE"
printf '  Workers:    %s\n' "$WORKERS"
printf '  Pkt floats: %s\n' "$PKT_FLOATS"
printf '  Sizes:      %s\n' "$SIZES"

port_busy() { ss -lun 2>/dev/null | grep -q ':9999'; }

free_port() {
    # Primary: kill whatever is bound to UDP 9999
    fuser -k -KILL 9999/udp 2>/dev/null || true
    # Secondary: known aggregator names
    pkill -KILL -f '[u]serspace_aggregator' 2>/dev/null || true
    pkill -KILL -f '[e]cho_aggregator'      2>/dev/null || true
    pkill -KILL -f '[x]dp_aggregator'       2>/dev/null || true
    # Tertiary: lsof-based
    if command -v lsof >/dev/null 2>&1; then
        lsof -t -iUDP:9999 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    fi
}

wait_port_free() {
    local i=0
    while [ $i -lt 20 ]; do
        port_busy || return 0
        free_port; sleep 0.5; i=$((i+1))
    done
    return 1
}

wait_port_listening() {
    local i=0
    while [ $i -lt 30 ]; do
        port_busy && return 0
        sleep 0.5; i=$((i+1))
    done
    return 1
}

free_port
if ! wait_port_free; then
    printf '  status=port_busy\n'
    { printf 'status=port_busy\n'; printf 'type=%s\n'  "$TYPE"
      printf 'workers=%s\n' "$WORKERS"; printf 'pkt_floats=%s\n' "$PKT_FLOATS"
      printf 'sizes=%s\n'   "$SIZES"; } > "$OUT/metadata.txt"
    exit 0
fi

MULTI=0
[ "$WORKERS" -gt 1 ] && MULTI=1

LOADER="$ROOT/ebpf/xdp_aggregator"
AGG_PID=""
GROUPED_ENV="0"
[ "$TYPE" = "userspace_grouped" ] && GROUPED_ENV="1"

case "$TYPE" in
    ebpf_xdp|xdp_pass)
        if [ ! -x "$LOADER" ]; then
            printf '  status=unavailable\n'
            printf '  reason: %s not built\n' "$LOADER"
            { printf 'status=unavailable\n'; printf 'type=%s\n'       "$TYPE"
              printf 'workers=%s\n'    "$WORKERS"
              printf 'pkt_floats=%s\n' "$PKT_FLOATS"
              printf 'sizes=%s\n'      "$SIZES"
              printf 'reason=no_loader\n'; } > "$OUT/metadata.txt"
            exit 0
        fi
        XDP_MODE=$([ "$TYPE" = "xdp_pass" ] && printf pass || printf native)
        setsid env NUM_WORKERS=$WORKERS PKT_FLOATS=$PKT_FLOATS XDP_MODE=$XDP_MODE \
            "$LOADER" > "$OUT/aggregator.log" 2>&1 < /dev/null &
        AGG_PID=$!
        ;;
    userspace|userspace_grouped)
        setsid env NUM_WORKERS=$WORKERS PKT_FLOATS=$PKT_FLOATS \
            GROUPED=$GROUPED_ENV TYPE=$TYPE \
            python3 "$ROOT/benchmarks/ablation/userspace_aggregator_silent.py" \
            > "$OUT/aggregator.log" 2>&1 < /dev/null &
        AGG_PID=$!
        ;;
    *)
        printf '  status=unknown_type\n'
        printf 'status=unknown_type\n' > "$OUT/metadata.txt"
        exit 0
        ;;
esac

if ! wait_port_listening; then
    printf '  status=failed_start\n'
    printf '  see %s/aggregator.log\n' "$OUT"
    { printf 'status=failed_start\n'; printf 'type=%s\n'       "$TYPE"
      printf 'workers=%s\n'    "$WORKERS"
      printf 'pkt_floats=%s\n' "$PKT_FLOATS"
      printf 'sizes=%s\n'      "$SIZES"; } > "$OUT/metadata.txt"
    printf '  --- aggregator.log tail ---\n'
    tail -5 "$OUT/aggregator.log" 2>/dev/null | sed 's/^/    /'
    kill -KILL "$AGG_PID" >/dev/null 2>&1 || true
    exit 0
fi

printf '  status=ok\n'
{ printf 'status=ok\n'; printf 'type=%s\n'       "$TYPE"
  printf 'workers=%s\n'    "$WORKERS"
  printf 'pkt_floats=%s\n' "$PKT_FLOATS"
  printf 'sizes=%s\n'      "$SIZES"
  printf 'pid=%s\n'        "$AGG_PID"; } > "$OUT/metadata.txt"

if [ "$MULTI" -eq 1 ]; then
    printf '  latency (skipped: multi-worker)\n'
    printf 'size_bytes,mean_us,median_us,p95_us,trimmed_mean_us\n' \
        > "$OUT/latency_results.csv"
    printf 'latency_skipped=multi-worker\n' >> "$OUT/metadata.txt"
else
    printf '  latency\n'
    [ -x "$ROOT/benchmarks/build/latency_benchmark" ] && \
        (cd "$ROOT/benchmarks/build" && \
         timeout 180 ./latency_benchmark 127.0.0.1 9999 0) \
            > "$OUT/latency_results.csv" 2>/dev/null || true
fi

printf '  scalability\n'
[ -x "$ROOT/benchmarks/build/scalability_benchmark" ] && \
    (cd "$ROOT/benchmarks/build" && \
     timeout 90 ./scalability_benchmark 127.0.0.1 9999 "$WORKERS") \
        > "$OUT/scalability_results.csv" 2>/dev/null || true

if [ "$MULTI" -eq 1 ]; then
    printf '  cpu (skipped: multi-worker)\n'
    printf 'cpu_skipped=multi-worker\n' >> "$OUT/metadata.txt"
else
    printf '  cpu\n'
    [ -x "$ROOT/benchmarks/build/cpu_benchmark" ] && \
        (cd "$ROOT/benchmarks/build" && \
         timeout 40 ./cpu_benchmark 127.0.0.1 9999 0 "$AGG_PID") \
            > "$OUT/cpu_results.txt" 2>/dev/null || true
fi

kill -TERM "$AGG_PID" >/dev/null 2>&1 || true
sleep 1
kill -KILL "$AGG_PID" >/dev/null 2>&1 || true
free_port
wait_port_free || true

if [ "$TYPE" = "ebpf_xdp" ] || [ "$TYPE" = "xdp_pass" ]; then
    rm -rf /sys/fs/bpf/xdp_aggregator /sys/fs/bpf/xdp_aggregator_pass 2>/dev/null || true
fi

ROWS=$(grep -cE '^[0-9]' "$OUT/latency_results.csv" 2>/dev/null) || ROWS=0
printf '  latency rows: %s\n' "$ROWS"