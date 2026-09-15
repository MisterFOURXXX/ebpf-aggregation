#!/bin/bash
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)

echo "Building project"
make -C ebpf >/dev/null

for dir in client_lib examples benchmarks tests; do
    cd "$ROOT/$dir"
    mkdir -p build
    cd build
    cmake -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY .. >/dev/null
    make --no-print-directory >/dev/null
done

cd "$ROOT"
mkdir -p benchmarks/results

echo "Binaries:"
ls -la ebpf/aggregator.bpf.o \
       client_lib/build/libswitchml.so \
       examples/build/simple_allreduce \
       benchmarks/build/latency_benchmark \
       benchmarks/build/scalability_benchmark \
       benchmarks/build/cpu_benchmark \
       tests/build/test_chunker \
       tests/build/test_packet_parse
echo "Build complete"