#!/bin/bash
# Remove all build artifacts and caches
echo "Cleaning all build directories..."
rm -rf client_lib/build tests/build examples/build benchmarks/build
rm -f tests/CMakeCache.txt examples/CMakeCache.txt benchmarks/CMakeCache.txt
echo "Done. Now run 'make all' to rebuild."