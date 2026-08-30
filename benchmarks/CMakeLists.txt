cmake_minimum_required(VERSION 3.16)
project(switchml_benchmarks CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Define executables
add_executable(latency_benchmark latency_benchmark.cpp)
add_executable(cpu_benchmark cpu_benchmark.cpp)
add_executable(scalability_benchmark scalability_benchmark.cpp)

# Target-scoped directory discovery and linking
foreach(target latency_benchmark cpu_benchmark scalability_benchmark)
    target_link_directories(${target} PRIVATE ${CMAKE_BINARY_DIR}/client_lib)
    target_link_libraries(${target} PRIVATE switchml pthread)
endforeach()