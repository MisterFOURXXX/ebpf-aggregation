cmake_minimum_required(VERSION 3.14)
project(eBPF_Agg CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -Wall -pthread")

# Client Library
add_subdirectory(client_lib)

# Benchmarks
add_subdirectory(benchmarks)

# Examples
add_subdirectory(examples)

# Tests (optional)
enable_testing()
add_subdirectory(tests)