#include "switchml.h"
#include <iostream>
#include <vector>
#include <chrono>

int main(int argc, char** argv) {
    if (argc < 4) { std::cerr << "Usage: latency_benchmark <ip> <port> <worker_id>\n"; return 1; }
    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int wid = std::atoi(argv[3]);

    std::vector<size_t> sizes = {64, 256, 1024, 4096, 16384, 65536, 262144, 1048576};
    switchml_init(ip, port, wid, 0x1234);
    std::cout << "size_bytes,latency_us\n";

    for (auto bytes : sizes) {
        size_t floats = bytes / sizeof(float);
        std::vector<float> send(floats, 1.0f), recv(floats, 0.0f);
        auto start = std::chrono::high_resolution_clock::now();
        if (switchml_allreduce(send.data(), recv.data(), floats) != 0) {
            std::cerr << "AllReduce failed at size " << bytes << "\n";
            break;
        }
        auto end = std::chrono::high_resolution_clock::now();
        auto us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();
        std::cout << bytes << "," << us << "\n";
    }
    switchml_finalize();
    return 0;
}