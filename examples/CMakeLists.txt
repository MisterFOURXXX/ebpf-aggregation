cmake_minimum_required(VERSION 3.16)

# 1. Define the executable target FIRST
add_executable(simple_allreduce simple_allreduce.cc)

# 2. Find required packages
find_package(Threads REQUIRED)

# 3. Link libraries to the defined target
target_link_libraries(simple_allreduce 
    PRIVATE 
        switchml 
        Threads::Threads
)

# 4. Set the output directory so the binary lands in build/examples/
set_target_properties(simple_allreduce PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/examples"
)