#!/bin/bash
cd "$(dirname "$0")/.."

echo "Removing build artifacts"
make -C ebpf clean > /dev/null 2>&1 || true
rm -rf client_lib/build tests/build examples/build benchmarks/build operator/bin
find . -name "CMakeCache.txt" -delete 2>/dev/null
find . -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null
find . -name "*.o" -delete 2>/dev/null
find . -name "*.so" -delete 2>/dev/null
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
mkdir -p benchmarks/results
echo "Cleanup complete"
