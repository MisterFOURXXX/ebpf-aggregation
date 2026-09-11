cmake_minimum_required(VERSION 3.10)
project(benchmarks)

set(CLIENT_BUILD_DIR ${CMAKE_SOURCE_DIR}/../client_lib/build)
set(CLIENT_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/../client_lib/include)
set(SWITCHML_LIB ${CLIENT_BUILD_DIR}/libswitchml.so)

if(NOT EXISTS ${SWITCHML_LIB})
    message(FATAL_ERROR "libswitchml.so not found at ${SWITCHML_LIB}")
endif()

include_directories(${CLIENT_INCLUDE_DIR})

add_executable(cpu_benchmark cpu_benchmark.cpp)
target_link_libraries(cpu_benchmark ${SWITCHML_LIB} pthread)

add_executable(latency_benchmark latency_benchmark.cpp)
target_link_libraries(latency_benchmark ${SWITCHML_LIB} pthread)

add_executable(scalability_benchmark scalability_benchmark.cpp)
target_link_libraries(scalability_benchmark ${SWITCHML_LIB} pthread)