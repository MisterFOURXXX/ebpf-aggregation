#!/bin/bash
# ============================================================
#  Master ablation runner
# ============================================================
set +m
set +b
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
CONFIGS="$ROOT/benchmarks/ablation/configs"
RESULTS="$ROOT/benchmarks/results/ablation"

echo "+-----------------------------------------------+"
echo "|   Ablation Study - eBPF-P4 Aggregation        |"
echo "+-----------------------------------------------+"

if [ ! -x "$ROOT/benchmarks/build/latency_benchmark" ]; then
    echo "> Building project"
    "$ROOT/scripts/build_all.sh" > /dev/null
fi

rm -rf "$RESULTS"
mkdir -p "$RESULTS"

ORDER="a1_ebpf_xdp a2_userspace a3_xdp_pass a4_no_agg \
       a5_pkt16 a5_pkt32 a5_pkt64 \
       a6_w1 a6_w2 a6_w4 a6_w8"

for cfg in $ORDER; do
    f="$CONFIGS/$cfg.conf"
    if [ ! -f "$f" ]; then
        echo "  [skip] $f not found"
        continue
    fi
    "$ROOT/benchmarks/ablation/run_one_ablation.sh" "$f" || \
        echo "  [warn] $cfg finished with non-zero exit"
done

echo ""
echo "> Generating comparison report"
python3 "$ROOT/benchmarks/ablation/analyze_ablation.py" || \
    echo "  [warn] analysis failed"

echo ""
echo "=== ALL ABLATIONS COMPLETE ==="
ls "$RESULTS" | sed 's/^/  /'
