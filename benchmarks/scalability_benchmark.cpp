// scalability_benchmark.cpp
// Measures real AllReduce latency as the number of workers scales (2, 4, 8, 16).
// Spawns real concurrent threads, each acting as an independent worker.
// Usage: ./scalability_benchmark <ip> <port> <max_workers> <num_floats> <iterations>
// Example: ./scalability_benchmark 192.168.1.100 9999 16 1024 100

#include "switchml.h"
#include <iostream>
#include <vector>
#include <thread>
#include <chrono>
#include <atomic>
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <numeric>

// ============================================================
// Thread-safe barrier using atomic counter
// ============================================================
class Barrier {
public:
    explicit Barrier(int count) : m_count(count), m_generation(0) {}

    void wait() {
        int gen = m_generation.load(std::memory_order_acquire);
        if (++m_counter == m_count) {
            // Last thread to arrive resets the counter and bumps the generation
            m_counter = 0;
            m_generation++;
        } else {
            // Wait for the next generation
            while (m_generation.load(std::memory_order_acquire) == gen) {
                std::this_thread::yield();
            }
        }
    }

private:
    const int m_count;
    std::atomic<int> m_counter{0};
    std::atomic<int> m_generation{0};
};

// ============================================================
// Worker Thread Function
// ============================================================
struct WorkerResult {
    int worker_id;
    double avg_latency_us;
    double min_latency_us;
    double max_latency_us;
    std::vector<double> latencies_us; // For p99 calculation
};

WorkerResult run_worker(const char* ip, int port, int worker_id,
                        uint32_t base_session_id, size_t num_floats,
                        int iterations, Barrier* barrier) {
    WorkerResult result;
    result.worker_id = worker_id;
    result.latencies_us.reserve(iterations);

    // Initialize client with a unique session ID (base + worker_id for isolation)
    uint32_t session_id = base_session_id + worker_id;

    if (switchml_init(ip, port, worker_id, session_id) != 0) {
        std::cerr << "[ERROR] Worker " << worker_id << " init failed" << std::endl;
        return result;
    }

    std::vector<float> sendbuf(num_floats, 1.0f);
    std::vector<float> recvbuf(num_floats, 0.0f);

    // Warm-up
    for (int i = 0; i < 5; ++i) {
        switchml_allreduce(sendbuf.data(), recvbuf.data(), num_floats);
    }

    // Synchronize all workers before starting the measurement
    barrier->wait();

    // Measure each iteration individually for accurate statistics
    for (int i = 0; i < iterations; ++i) {
        auto start = std::chrono::high_resolution_clock::now();
        int ret = switchml_allreduce(sendbuf.data(), recvbuf.data(), num_floats);
        auto end = std::chrono::high_resolution_clock::now();

        if (ret == 0) {
            double us = std::chrono::duration<double, std::micro>(end - start).count();
            result.latencies_us.push_back(us);
        }
    }

    switchml_finalize();

    // Compute statistics
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

// ============================================================
// Main Entry Point
// ============================================================
int main(int argc, char** argv) {
    // --- 1. Parse Arguments ---
    if (argc < 6) {
        std::cerr << "Usage: " << argv[0]
                  << " <ip> <port> <max_workers> <num_floats> <iterations>"
                  << std::endl;
        std::cerr << "Example: " << argv[0]
                  << " 192.168.1.100 9999 16 1024 100"
                  << std::endl;
        return EXIT_FAILURE;
    }

    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int max_workers = std::atoi(argv[3]);
    size_t num_floats = static_cast<size_t>(std::atoi(argv[4]));
    int iterations = std::atoi(argv[5]);

    if (max_workers < 2 || max_workers > 32) {
        std::cerr << "[ERROR] max_workers must be between 2 and 32" << std::endl;
        return EXIT_FAILURE;
    }

    std::cout << "=== Scalability Benchmark ===" << std::endl;
    std::cout << " Aggregator:   " << ip << ":" << port << std::endl;
    std::cout << " Max Workers:  " << max_workers << std::endl;
    std::cout << " Tensor Size:  " << num_floats << " floats ("
              << (num_floats * sizeof(float)) / (1024.0) << " KB)" << std::endl;
    std::cout << " Iterations:   " << iterations << std::endl;

    // --- 2. CSV Header ---
    std::cout << "\n[CSV] workers,avg_latency_us,min_latency_us,max_latency_us,p99_latency_us\n";

    // --- 3. Run for different worker counts (2, 4, 8, ..., max_workers) ---
    for (int num_workers = 2; num_workers <= max_workers; num_workers *= 2) {
        std::cout << "\n--- Testing with " << num_workers << " workers ---" << std::endl;

        Barrier barrier(num_workers);
        uint32_t base_session_id = 0x10000000 | num_workers;

        // Launch threads
        std::vector<std::thread> threads;
        std::vector<WorkerResult> results(num_workers);

        for (int w = 0; w < num_workers; ++w) {
            threads.emplace_back(
                [&, w]() {
                    results[w] = run_worker(ip, port, w, base_session_id,
                                            num_floats, iterations, &barrier);
                }
            );
        }

        // Wait for all threads to finish
        for (auto& t : threads) {
            t.join();
        }

        // --- 4. Aggregate results from all workers ---
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
            std::cerr << "[ERROR] No successful iterations for " << num_workers << " workers" << std::endl;
            continue;
        }

        std::sort(all_latencies.begin(), all_latencies.end());

        double avg = std::accumulate(all_latencies.begin(), all_latencies.end(), 0.0) /
                     all_latencies.size();
        double min_val = all_latencies.front();
        double max_val = all_latencies.back();

        // Compute p99 (99th percentile)
        size_t idx_p99 = static_cast<size_t>(0.99 * all_latencies.size());
        if (idx_p99 >= all_latencies.size()) idx_p99 = all_latencies.size() - 1;
        double p99 = all_latencies[idx_p99];

        std::cout << "Total successful samples: " << total_success << " / "
                  << (num_workers * iterations) << std::endl;

        // CSV output: workers,avg,min,max,p99
        std::cout << std::fixed << std::setprecision(2);
        std::cout << "[CSV] " << num_workers << ","
                  << avg << ","
                  << min_val << ","
                  << max_val << ","
                  << p99 << std::endl;
    }

    std::cout << "\n=== Done ===" << std::endl;
    std::cout << "Run python benchmarks/analysis/plot_scalability.py to generate graph." << std::endl;

    return EXIT_SUCCESS;
}