link_directories(${CMAKE_BINARY_DIR}/client_lib)
add_executable(simple_allreduce simple_allreduce.cc)
target_link_libraries(simple_allreduce switchml pthread)