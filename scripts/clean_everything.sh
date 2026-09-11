#!/bin/bash
# ============================================================
# Full Project Cleanup - Removes ALL generated artifacts.
# Returns the repository to a fresh source-only state.
# ============================================================
cd "$(dirname "$0")/.."
ROOT=$(pwd)

echo "Starting full project cleanup..."

# 1. Run standard make clean (eBPF, clients, etc.)
if [ -f Makefile ]; then
    make clean > /dev/null 2>&1 || true
fi

# 2. Remove all build directories
echo "Removing build directories..."
rm -rf client_lib/build tests/build examples/build benchmarks/build operator/bin

# 3. Remove CMake caches
echo "Removing CMake caches..."
find . -name "CMakeCache.txt" -delete 2>/dev/null
find . -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null

# 4. Remove compiled binaries and objects
echo "Removing compiled binaries and objects..."
find . -name "*.o" -delete 2>/dev/null
find . -name "*.so" -delete 2>/dev/null
find . -name "*.bpf.o" -delete 2>/dev/null

# 5. Remove Python caches
echo "Removing Python caches..."
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
find . -name "*.pyc" -delete 2>/dev/null

# 6. Remove experiment results
echo "Removing experiment results..."
rm -f benchmarks/results/*.csv
rm -f benchmarks/results/*.txt
rm -f benchmarks/results/*.log

# 7. Remove generated plot images
echo "Removing plot images..."
rm -f benchmarks/analysis/*.png

# 8. Remove temporary Kubernetes/Docker artifacts
echo "Removing Kubernetes/Docker temporary files..."
rm -f kubeconfig 2>/dev/null || true

echo "Full cleanup complete. The repository is now in a clean source-only state."
ls -la
