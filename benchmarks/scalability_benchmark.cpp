#include "switchml.h"
#include <thread>
#include <vector>
#include <chrono>
#include <iostream>
#include <atomic>

std::atomic<int> ready_count{0};

void worker_thread(const char* ip, int port, int wid, size_t floats, int iters) {
    switchml_init(ip, port, wid, 0x1234);
    std::vector<float> send(floats, 1.0f), recv(floats, 0.0f);
    ready_count++;
    while (ready_count.load() < 8) std::this_thread::yield();

    auto start = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < iters; i++) {
        switchml_allreduce(send.data(), recv.data(), floats);
    }
    auto end = std::chrono::high_resolution_clock::now();
    auto us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count() / iters;
    std::cout << wid << "," << us << "\n";
    switchml_finalize();
}

int main() {
    const char* ip = "192.168.1.100";
    int port = 9999;
    std::vector<std::thread> threads;
    for (int w = 0; w < 8; w++)
        threads.emplace_back(worker_thread, ip, port, w, 1024, 100);
    for (auto &t : threads) t.join();
    return 0;
}