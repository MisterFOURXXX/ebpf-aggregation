#!/bin/bash
# ============================================================
# build.sh - Build eBPF, client library, examples, benchmarks, tests
# ============================================================
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)

echo "Building everything"
make -C ebpf > /dev/null

cd client_lib && mkdir -p build && cd build
cmake -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY .. > /dev/null
make --no-print-directory > /dev/null
cd "$ROOT"

cd examples && mkdir -p build && cd build
cmake -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY .. > /dev/null
make --no-print-directory > /dev/null
cd "$ROOT"

cd benchmarks && mkdir -p build && cd build
cmake -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY .. > /dev/null
make --no-print-directory > /dev/null
cd "$ROOT"

cd tests && mkdir -p build && cd build
cmake -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY .. > /dev/null
make --no-print-directory > /dev/null
cd "$ROOT"

mkdir -p benchmarks/results

echo "Binaries built:"
ls -la ebpf/aggregator.bpf.o \
       client_lib/build/libswitchml.so \
       examples/build/simple_allreduce \
       benchmarks/build/latency_benchmark \
       benchmarks/build/scalability_benchmark \
       benchmarks/build/cpu_benchmark \
       tests/build/test_chunker \
       tests/build/test_packet_parse
echo "Build complete"
