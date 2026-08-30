#include "switchml.h"
#include <iostream>
#include <vector>
#include <thread>
#include <chrono>
#include <atomic>
#include <algorithm>
#include <numeric>
#include <iomanip>
#include <cstdlib>

// ----- Barrier for synchronising workers -----
class Barrier {
public:
    explicit Barrier(int count) : m_count(count), m_counter(0), m_generation(0) {}
    void wait() {
        int gen = m_generation.load(std::memory_order_acquire);
        if (++m_counter == m_count) {
            m_counter = 0;
            m_generation++;
        } else {
            while (m_generation.load(std::memory_order_acquire) == gen) {
                std::this_thread::yield();
            }
        }
    }
private:
    const int m_count;
    std::atomic<int> m_counter;
    std::atomic<int> m_generation;
};

// ----- Result structure -----
struct WorkerResult {
    int worker_id;
    double avg_latency_us;
    double min_latency_us;
    double max_latency_us;
    std::vector<double> latencies_us;
};

// ----- Worker thread function -----
WorkerResult run_worker(const char* ip, int port, int worker_id,
                        size_t num_ints, int iterations, Barrier* barrier) {
    WorkerResult result;
    result.worker_id = worker_id;
    result.latencies_us.reserve(iterations);

    if (switchml_init(ip, port, worker_id) != 0) {
        std::cerr << "Worker " << worker_id << " init failed\n";
        return result;
    }

    std::vector<int32_t> sendbuf(num_ints, 1);
    std::vector<int32_t> recvbuf(num_ints, 0);

    // Warmup
    for (int i = 0; i < 5; ++i) {
        switchml_allreduce(sendbuf.data(), recvbuf.data(), num_ints);
    }

    barrier->wait();

    for (int i = 0; i < iterations; ++i) {
        auto start = std::chrono::high_resolution_clock::now();
        int ret = switchml_allreduce(sendbuf.data(), recvbuf.data(), num_ints);
        auto end = std::chrono::high_resolution_clock::now();
        if (ret == 0) {
            double us = std::chrono::duration<double, std::micro>(end - start).count();
            result.latencies_us.push_back(us);
        }
    }

    switchml_finalize();

    if (!result.latencies_us.empty()) {
        std::sort(result.latencies_us.begin(), result.latencies_us.end());
        result.min_latency_us = result.latencies_us.front();
        result.max_latency_us = result.latencies_us.back();
        result.avg_latency_us = std::accumulate(result.latencies_us.begin(),
                                                result.latencies_us.end(), 0.0) /
                               result.latencies_us.size();
    }
    return result;
}

// ----- Main benchmark -----
int main(int argc, char** argv) {
    if (argc < 6) {
        std::cerr << "Usage: ./scalability_benchmark <ip> <port> <max_workers> <num_ints> <iterations>\n";
        return 1;
    }

    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int max_workers = std::atoi(argv[3]);
    size_t num_ints = static_cast<size_t>(std::atoi(argv[4]));
    int iterations = std::atoi(argv[5]);

    if (max_workers < 2 || max_workers > 32) {
        std::cerr << "max_workers must be between 2 and 32\n";
        return 1;
    }

    std::cout << "=== Scalability Benchmark ===\n";
    std::cout << "Aggregator: " << ip << ":" << port << "\n";
    std::cout << "Max Workers: " << max_workers << "\n";
    std::cout << "Tensor size: " << num_ints << " integers ("
              << (num_ints * sizeof(int32_t)) / 1024.0 << " KB)\n";
    std::cout << "Iterations per worker: " << iterations << "\n";

    std::cout << "\n[CSV] workers,avg_latency_us,min_latency_us,max_latency_us,p99_latency_us\n";

    for (int num_workers = 2; num_workers <= max_workers; num_workers *= 2) {
        std::cout << "\n--- Testing with " << num_workers << " workers ---\n";
        Barrier barrier(num_workers);

        std::vector<std::thread> threads;
        std::vector<WorkerResult> results(num_workers);

        for (int w = 0; w < num_workers; ++w) {
            threads.emplace_back([&, w]() {
                results[w] = run_worker(ip, port, w, num_ints, iterations, &barrier);
            });
        }

        for (auto& t : threads) t.join();

        std::vector<double> all_latencies;
        int total_success = 0;
        for (const auto& r : results) {
            if (!r.latencies_us.empty()) {
                all_latencies.insert(all_latencies.end(),
                                     r.latencies_us.begin(),
                                     r.latencies_us.end());
                total_success += r.latencies_us.size();
            }
        }

        if (all_latencies.empty()) {
            std::cerr << "No successful iterations for " << num_workers << " workers\n";
            continue;
        }

        std::sort(all_latencies.begin(), all_latencies.end());

        double avg = std::accumulate(all_latencies.begin(), all_latencies.end(), 0.0) /
                     all_latencies.size();
        double min_val = all_latencies.front();
        double max_val = all_latencies.back();
        size_t idx_p99 = static_cast<size_t>(0.99 * all_latencies.size());
        if (idx_p99 >= all_latencies.size()) idx_p99 = all_latencies.size() - 1;
        double p99 = all_latencies[idx_p99];

        std::cout << std::fixed << std::setprecision(2);
        std::cout << "Successful samples: " << total_success << "/" << (num_workers * iterations) << "\n";
        std::cout << "[CSV] " << num_workers << ","
                  << avg << "," << min_val << "," << max_val << "," << p99 << "\n";
    }

    std::cout << "\nDone.\n";
    return 0;
}