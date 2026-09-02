cmake_minimum_required(VERSION 3.10)
project(tests)
enable_testing()

# Point to the client library build and include directories
set(CLIENT_BUILD ${CMAKE_SOURCE_DIR}/../client_lib/build)
set(CLIENT_INCLUDE ${CMAKE_SOURCE_DIR}/../client_lib/include)
link_directories(${CLIENT_BUILD})
include_directories(${CLIENT_INCLUDE})

add_executable(test_chunker test_chunker.cpp)
target_link_libraries(test_chunker switchml pthread)
add_test(NAME ChunkerTest COMMAND test_chunker)

add_executable(test_packet_parse test_packet_parse.cpp)
target_link_libraries(test_packet_parse switchml pthread)
add_test(NAME PacketParseTest COMMAND test_packet_parse)