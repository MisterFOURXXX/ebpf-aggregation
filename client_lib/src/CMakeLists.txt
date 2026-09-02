add_library(switchml SHARED
    switchml.cpp
    chunker.cpp
    udp_client.cpp
)
target_include_directories(switchml PUBLIC 
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(switchml pthread)
install(TARGETS switchml LIBRARY DESTINATION lib)