cmake_minimum_required(VERSION 3.10)
project(examples)

set(CLIENT_BUILD_DIR ${CMAKE_SOURCE_DIR}/../client_lib/build)
set(CLIENT_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/../client_lib/include)
set(SWITCHML_LIB ${CLIENT_BUILD_DIR}/libswitchml.so)

if(NOT EXISTS ${SWITCHML_LIB})
    message(FATAL_ERROR "libswitchml.so not found at ${SWITCHML_LIB}")
endif()

include_directories(${CLIENT_INCLUDE_DIR})

add_executable(simple_allreduce simple_allreduce.cc)
target_link_libraries(simple_allreduce ${SWITCHML_LIB} pthread)