#include "switchml.h"
#include <iostream>
#include <vector>
#include <cstring>
#include <errno.h>

int main(int argc, char** argv) {
    if (argc < 4) { 
        std::cerr << "Usage: simple_allreduce <ip> <port> <worker_id>\n"; 
        return 1; 
    }
    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int wid = std::atoi(argv[3]);

    std::cout << "=== Starting SwitchML Client ===" << std::endl;
    std::cout << "IP: " << ip << ", Port: " << port << ", Worker ID: " << wid << std::endl;

    int ret = switchml_init(ip, port, wid, 0xABCD);
    std::cout << "switchml_init returned: " << ret << std::endl;
    if (ret != 0) {
        std::cerr << "Init failed with code: " << ret << std::endl;
        std::cerr << "errno: " << errno << " (" << strerror(errno) << ")" << std::endl;
        return 1;
    }

    const size_t N = 1024;
    std::vector<float> send(N, 1.0f);
    std::vector<float> recv(N, 0.0f);
    
    std::cout << "Calling switchml_allreduce with " << N << " floats..." << std::endl;
    ret = switchml_allreduce(send.data(), recv.data(), N);
    std::cout << "switchml_allreduce returned: " << ret << std::endl;
    
    if (ret == 0) {
        std::cout << "AllReduce succeeded. First result: " << recv[0] << std::endl;
    } else {
        std::cerr << "AllReduce failed with code: " << ret << std::endl;
        std::cerr << "errno: " << errno << " (" << strerror(errno) << ")" << std::endl;
    }

    switchml_finalize();
    return 0;
}
