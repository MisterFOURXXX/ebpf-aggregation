cmake_minimum_required(VERSION 3.10)
project(benchmarks)

get_filename_component(PROJECT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/.. ABSOLUTE)
set(CLIENT_LIB_DIR ${PROJECT_ROOT}/client_lib/build)
link_directories(${CLIENT_LIB_DIR})
include_directories(${PROJECT_ROOT}/client_lib/include)

add_executable(cpu_benchmark cpu_benchmark.cpp)
target_link_libraries(cpu_benchmark switchml pthread)

add_executable(latency_benchmark latency_benchmark.cpp)
target_link_libraries(latency_benchmark switchml pthread)

add_executable(scalability_benchmark scalability_benchmark.cpp)
target_link_libraries(scalability_benchmark switchml pthread)