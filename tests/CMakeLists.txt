cmake_minimum_required(VERSION 3.10)
project(tests)
enable_testing()

set(CLIENT_BUILD_DIR ${CMAKE_SOURCE_DIR}/../client_lib/build)
set(CLIENT_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/../client_lib/include)
set(SWITCHML_LIB ${CLIENT_BUILD_DIR}/libswitchml.so)

if(NOT EXISTS ${SWITCHML_LIB})
    message(FATAL_ERROR "libswitchml.so not found at ${SWITCHML_LIB}")
endif()

message(STATUS "Using library: ${SWITCHML_LIB}")

include_directories(${CLIENT_INCLUDE_DIR})

add_executable(test_chunker test_chunker.cpp)
target_link_libraries(test_chunker ${SWITCHML_LIB} pthread)

add_executable(test_packet_parse test_packet_parse.cpp)
target_link_libraries(test_packet_parse ${SWITCHML_LIB} pthread)

add_test(NAME ChunkerTest COMMAND test_chunker)
add_test(NAME PacketParseTest COMMAND test_packet_parse)
