#!/bin/bash
# Complete test script for eBPF Aggregation

cd /root/ebpf-aggregation

echo "=== 1. Clean and Build ==="
./scripts/clean_all.sh
make clean
make all

echo "=== 2. Run Unit Tests ==="
cd tests
mkdir -p build && cd build
cmake .. && make
ctest --output-on-failure
cd ../..

echo "=== 3. Build Examples and Benchmarks ==="
cd examples && mkdir -p build && cd build
cmake .. && make
cd ../..

cd benchmarks && mkdir -p build && cd build
cmake .. && make
cd ../..

echo "=== 4. Test with Userspace Aggregator ==="
pkill -f userspace_aggregator 2>/dev/null
python3 benchmarks/ablation/userspace_aggregator_fixed.py &
sleep 3

echo "=== 5. Test Example ==="
cd examples/build
./simple_allreduce 127.0.0.1 9999 0
cd ../..

echo "=== 6. Run Latency Benchmark ==="
cd benchmarks/build
./latency_benchmark 127.0.0.1 9999 0
cd ../..

echo "=== 7. Run Scalability Benchmark ==="
cd benchmarks/build
./scalability_benchmark
cd ../..

echo "=== 8. Install Plotting Dependencies ==="
sudo apt install -y python3-matplotlib python3-pandas 2>/dev/null || true

echo "=== 9. Generate Plots ==="
cd benchmarks/analysis
python3 plot_latency.py
python3 plot_scalability.py
python3 plot_cpu_usage.py
cd ../..

echo "=== 10. Test XDP ==="
sudo ./scripts/attach_xdp.sh lo
cd examples/build
./simple_allreduce 127.0.0.1 9999 0
sudo bpftool net detach xdp dev lo
cd ../..

echo "=== 11. Cleanup ==="
pkill -f userspace_aggregator 2>/dev/null

echo "=== ALL TESTS COMPLETE! ==="
