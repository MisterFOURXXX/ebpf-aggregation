#!/bin/bash
# ============================================================
# run_ablation.sh - build and run full ablation study
# ============================================================
set +m
cd "$(dirname "$0")/.."
ROOT=$(pwd)

echo "Building project"
bash "$ROOT/scripts/build.sh"

echo "Running ablation study"
bash "$ROOT/benchmarks/ablation/run_ablation.sh"

echo "Ablation complete"
echo "Per-config results: $ROOT/benchmarks/results/ablation/<name>/"
echo "Report files:"
echo "  $ROOT/benchmarks/results/ablation/_report/ablation_report.png"
echo "  $ROOT/benchmarks/results/ablation/_report/combined_summary.csv"
echo "  $ROOT/benchmarks/results/ablation/_report/combined_latency.csv"