#!/bin/bash
echo "Removing all build directories and CMake caches..."
rm -rf client_lib/build
rm -rf tests/build
rm -rf examples/build
rm -rf benchmarks/build
rm -rf operator/bin
find . -name "CMakeCache.txt" -delete
find . -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null
echo "Cleanup complete."