#!/bin/bash
echo "Ablation: compare userspace vs eBPF aggregator"
sudo pkill -f userspace_aggregator || true
sudo python3 benchmarks/ablation/userspace_aggregator.py &
sleep 1
echo "Run benchmarks now against userspace aggregator"
# In a real experiment, you would run the benchmark and record results.