cmake_minimum_required(VERSION 3.14)
project(eBPF_Agg CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -Wall -pthread")

add_subdirectory(client_lib)
add_subdirectory(benchmarks)
add_subdirectory(examples)
# add_subdirectory(tests)   # optional