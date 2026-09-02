cmake_minimum_required(VERSION 3.10)
project(examples)

get_filename_component(PROJECT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/.. ABSOLUTE)
set(CLIENT_LIB_DIR ${PROJECT_ROOT}/client_lib/build)
link_directories(${CLIENT_LIB_DIR})
include_directories(${PROJECT_ROOT}/client_lib/include)

add_executable(simple_allreduce simple_allreduce.cc)
target_link_libraries(simple_allreduce switchml pthread)