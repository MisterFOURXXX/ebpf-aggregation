#!/bin/bash
# Top-level wrapper: build + run entire ablation study
set +m
set +b
cd "$(dirname "$0")/.."
ROOT=$(pwd)

echo "=== Building project ==="
"$ROOT/scripts/build_all.sh"

echo ""
echo "=== Running ablation study ==="
"$ROOT/benchmarks/ablation/run_ablation.sh"

echo ""
echo "=== Ablation complete ==="
echo "Results: $ROOT/benchmarks/results/ablation"
echo "Report:  $ROOT/benchmarks/results/ablation/_report"
ls "$ROOT/benchmarks/results/ablation/_report" 2>/dev/null | sed 's/^/  /'
