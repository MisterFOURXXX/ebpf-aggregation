add_library(switchml SHARED
    switchml.cpp
    chunker.cpp
    udp_client.cpp
)

# Set the output directory to build/ (not build/src/)
set_target_properties(switchml PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}
)

target_include_directories(switchml PUBLIC 
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(switchml pthread)
install(TARGETS switchml LIBRARY DESTINATION lib)