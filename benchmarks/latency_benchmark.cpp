#include "switchml.h"
#include <chrono>
#include <iostream>
#include <vector>
#include <cstdlib>
#include <unistd.h>
#include <sched.h>
#include <pthread.h>

#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>
#define cpu_relax() _mm_pause()
#else
#define cpu_relax() asm volatile("yield" ::: "memory")
#endif

#define likely(x)   __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)

inline bool execute_allreduce_with_backoff(int32_t* __restrict sendbuf,
                                           int32_t* __restrict recvbuf,
                                           size_t num_ints) noexcept {
    int retries = 0;
    while (retries < 200) { // Increased max retry budget for network convergence
        if (switchml_allreduce(sendbuf, recvbuf, num_ints) == 0)
            return true;
        ++retries;
        if (retries < 4) cpu_relax();
        else if (retries < 8) sched_yield();
        else usleep(10);
    }
    return false;
}

int main(int argc, char** argv) {
    std::cin.tie(nullptr);

    if (argc < 6) {
        std::cerr << "Usage: ./latency_benchmark <aggregator_ip> <port> <worker_id> <num_ints> <iterations> [cpu_core]\n";
        return 1;
    }

    const char* ip = argv[1];
    const int port = std::atoi(argv[2]);
    const int wid = std::atoi(argv[3]);
    const size_t num_ints = static_cast<size_t>(std::atoi(argv[4]));
    const int iters = std::atoi(argv[5]);

    if (argc >= 7) {
        int core = std::atoi(argv[6]);
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        CPU_SET(core, &cpuset);
        pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
    }

    std::cout << "[INFO] Worker " << wid << " initializing target " << ip << ":" << port << "..." << std::endl;

    if (unlikely(switchml_init(ip, port, wid) < 0)) {
        std::cerr << "[ERROR] Worker " << wid << " init failed!" << std::endl;
        return 1;
    }

    std::vector<int32_t> sendbuf(num_ints, 1);
    std::vector<int32_t> recvbuf(num_ints, 0);

    // Reset sequence state before warmup
    switchml_reset_seq(0);

    std::cout << "[INFO] Worker " << wid << " starting warmup..." << std::endl;
    for (int i = 0; i < 2; ++i) {
        if (!execute_allreduce_with_backoff(sendbuf.data(), recvbuf.data(), num_ints)) {
            std::cerr << "[ERROR] Worker " << wid << " warmup " << i << " failed. Aborting." << std::endl;
            switchml_finalize();
            return 1;
        }
    }

    std::cout << "[INFO] Worker " << wid << " starting benchmark (" << iters << " iterations)..." << std::endl;

    const auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < iters; ++i) {
        if (unlikely(!execute_allreduce_with_backoff(sendbuf.data(), recvbuf.data(), num_ints))) {
            std::cerr << "[ERROR] Worker " << wid << " AllReduce failed at iteration " << i << std::endl;
            switchml_finalize();
            return 1;
        }
    }
    const auto end = std::chrono::steady_clock::now();

    const double elapsed_us = std::chrono::duration<double, std::micro>(end - start).count();
    const double avg_latency = elapsed_us / static_cast<double>(iters);

    std::cout << "\n==================================================\n"
              << "[SUCCESS] Worker ID: " << wid << "\n"
              << "Iterations: " << iters << "\n"
              << "Avg Latency: " << avg_latency << " us\n"
              << "==================================================" << std::endl;

    switchml_finalize();
    return 0;
}