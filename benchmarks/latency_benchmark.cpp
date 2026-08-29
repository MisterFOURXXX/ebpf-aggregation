// latency_benchmark.cpp
#include "switchml.h"
#include <chrono>
#include <iostream>
#include <vector>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc < 6) {
        std::cerr << "Usage: ./latency_benchmark <ip> <port> <worker_id> <num_floats> <iterations>\n";
        return 1;
    }
    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int wid = std::atoi(argv[3]);
    size_t num_floats = std::atoi(argv[4]);
    int iters = std::atoi(argv[5]);

    if (switchml_init(ip, port, wid) < 0) {
        std::cerr << "Failed to init\n";
        return 1;
    }

    std::vector<float> sendbuf(num_floats, 1.0f);
    std::vector<float> recvbuf(num_floats, 0.0f);

    // Warmup
    for (int i = 0; i < 10; i++) switchml_allreduce(sendbuf.data(), recvbuf.data(), num_floats);

    auto start = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < iters; i++) {
        if (switchml_allreduce(sendbuf.data(), recvbuf.data(), num_floats) < 0) {
            std::cerr << "AllReduce failed at iteration " << i << "\n";
            break;
        }
    }
    auto end = std::chrono::high_resolution_clock::now();
    auto us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();

    std::cout << "Avg latency: " << (us / iters) << " us\n";
    switchml_finalize();
    return 0;
}