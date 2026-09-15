#!/bin/bash
# ============================================================
# run_ablation.sh
#   --quick    run only A2 and A4 to validate the harness
#   (default)  run all 11 configurations
# ============================================================
set +m
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT="$ROOT/benchmarks/results/ablation"

QUICK=0
[ "$1" = "--quick" ] && QUICK=1

RUN="$ROOT/benchmarks/ablation/run_one_ablation.sh"

if [ $QUICK -eq 1 ]; then
    printf 'Quick ablation (A2 + A4) - validation run\n'
    mkdir -p "$OUT"
    bash "$RUN" A2 userspace 1 64 64 256 1024 4096 16384 65536
    bash "$RUN" A4 userspace 1 64 64 256 1024 4096 16384 65536
    exit 0
fi

printf 'Ablation study - eBPF-P4 Aggregation\n'
mkdir -p "$OUT"

# arg layout:   NAME          TYPE                WORKERS  PKT_FLOATS  SIZE1 SIZE2 ...
#                                                                       ^
# IMPORTANT: two consecutive 64s. The first is PKT_FLOATS, the second
# is the first payload size. If you only write one 64, the first
# payload size is consumed as PKT_FLOATS.

bash "$RUN" A1       ebpf_xdp           1 64 64 256 1024 4096 16384 65536
bash "$RUN" A2       userspace          1 64 64 256 1024 4096 16384 65536
bash "$RUN" A3       xdp_pass           1 64 64 256 1024 4096 16384 65536
bash "$RUN" A4       userspace          1 64 64 256 1024 4096 16384 65536
bash "$RUN" A5-pkt16 userspace          1 16 64 256 1024 4096 16384 65536
bash "$RUN" A5-pkt32 userspace          1 32 64 256 1024 4096 16384 65536
bash "$RUN" A5-pkt64 userspace          1 64 64 256 1024 4096 16384 65536
bash "$RUN" A6-w1    userspace_grouped  1 64 256
bash "$RUN" A6-w2    userspace_grouped  2 64 256
bash "$RUN" A6-w4    userspace_grouped  4 64 256
bash "$RUN" A6-w8    userspace_grouped  8 64 256

printf 'Combining results\n'
python3 "$ROOT/benchmarks/ablation/combine_results.py" \
    --input  "$OUT" --output "$OUT"

printf 'Plotting\n'
python3 "$ROOT/benchmarks/analysis/plot_ablation.py" \
    --input  "$OUT" --output "$OUT"

printf 'Ablation complete\n'
printf 'Results: %s\n'  "$OUT"
printf 'Report:  %s\n' "$OUT/_report"
ls "$OUT"/combined_*.csv      2>/dev/null | sed 's/^/  /'
ls "$OUT"/ablation_report.png 2>/dev/null | sed 's/^/  /'