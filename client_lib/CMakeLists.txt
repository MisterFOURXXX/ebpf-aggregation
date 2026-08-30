add_library(switchml SHARED src/udp_client.cpp)
target_include_directories(switchml PUBLIC include)
target_link_libraries(switchml pthread)

install(TARGETS switchml DESTINATION lib)
install(DIRECTORY include/ DESTINATION include)