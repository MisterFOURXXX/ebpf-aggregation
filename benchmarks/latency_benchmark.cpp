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
    while (retries < 10) {
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
    std::ios_base::sync_with_stdio(false);
    std::cin.tie(nullptr);

    if (argc < 6) {
        std::cerr << "Usage: ./latency_benchmark <ip> <port> <worker_id> <num_ints> <iterations>\n";
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

    if (unlikely(switchml_init(ip, port, wid) < 0)) {
        std::cerr << "[ERROR] Init failed\n";
        return 1;
    }

    std::vector<int32_t> sendbuf(num_ints, 1);
    std::vector<int32_t> recvbuf(num_ints, 0);
    for (size_t i = 0; i < num_ints; i += 16) {
        sendbuf[i] = 1;
        recvbuf[i] = 0;
        __builtin_prefetch(&sendbuf[i + 16], 0, 3);
        __builtin_prefetch(&recvbuf[i + 16], 0, 3);
    }

    for (int i = 0; i < 2; ++i)
        if (!execute_allreduce_with_backoff(sendbuf.data(), recvbuf.data(), num_ints))
            std::cerr << "[WARN] warmup " << i << " failed\n";

    switchml_reset_seq(10);

    const auto start = std::chrono::steady_clock::now();
    auto* allreduce_fn = &switchml_allreduce;
    for (int i = 0; i < iters; ++i) {
        if (unlikely((*allreduce_fn)(sendbuf.data(), recvbuf.data(), num_ints) < 0)) {
            std::cerr << "\n[ERROR] AllReduce failed at iteration " << i << "\n";
            switchml_finalize();
            return 1;
        }
        __builtin_prefetch(sendbuf.data(), 0, 3);
        __builtin_prefetch(recvbuf.data(), 0, 3);
    }
    const auto end = std::chrono::steady_clock::now();

    const double elapsed_us = std::chrono::duration<double, std::micro>(end - start).count();
    const double avg_latency = elapsed_us / static_cast<double>(iters);

    std::cout << "\n==================================================\n";
    std::cout << "[SUCCESS] Worker ID: " << wid << "\n";
    std::cout << "Iterations: " << iters << "\n";
    std::cout << "Avg Latency: " << avg_latency << " us\n";
    std::cout << "==================================================\n";

    switchml_finalize();
    return 0;
}