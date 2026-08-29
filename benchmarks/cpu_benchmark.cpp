// cpu_benchmark.cpp
// ACCURATE CPU utilization measurement using /proc/stat delta
// Usage: ./cpu_benchmark <ip> <port> <worker_id> <session_id> <num_floats> <iterations>
// Example: ./cpu_benchmark 192.168.1.100 9999 0 0x12345678 16777216 100

#include "switchml.h"
#include <iostream>
#include <vector>
#include <fstream>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <iomanip>
#include <numeric>

// ============================================================
// CPU Time Structure (matches /proc/stat fields)
// ============================================================
struct CpuTime {
    unsigned long long user;      // Time spent in user mode
    unsigned long long nice;      // Time spent in user mode with low priority
    unsigned long long system;    // Time spent in kernel mode
    unsigned long long idle;      // Time spent idle
    unsigned long long iowait;    // Time waiting for I/O
    unsigned long long irq;       // Time servicing hardware interrupts
    unsigned long long softirq;   // Time servicing software interrupts
    unsigned long long steal;     // Time stolen by other VMs

    // Total CPU time since boot
    unsigned long long total() const {
        return user + nice + system + idle + iowait + irq + softirq + steal;
    }

    // Busy time (total - idle - iowait)
    unsigned long long busy() const {
        return total() - idle - iowait;
    }
};

// ============================================================
// Read /proc/stat safely
// ============================================================
CpuTime read_cpu_time() {
    std::ifstream stat("/proc/stat");
    if (!stat.is_open()) {
        std::cerr << "[ERROR] Cannot open /proc/stat" << std::endl;
        exit(EXIT_FAILURE);
    }

    std::string line;
    std::getline(stat, line);
    stat.close();

    CpuTime t{};
    // Format: cpu  user nice system idle iowait irq softirq steal
    int parsed = sscanf(line.c_str(), "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
                        &t.user, &t.nice, &t.system, &t.idle,
                        &t.iowait, &t.irq, &t.softirq, &t.steal);
    if (parsed != 8) {
        std::cerr << "[ERROR] Failed to parse /proc/stat. Parsed: " << parsed << std::endl;
        exit(EXIT_FAILURE);
    }
    return t;
}

// ============================================================
// Main Benchmark
// ============================================================
int main(int argc, char** argv) {
    // --- 1. Parse Arguments ---
    if (argc < 7) {
        std::cerr << "Usage: " << argv[0]
                  << " <aggregator_ip> <port> <worker_id> <session_id> <num_floats> <iterations>"
                  << std::endl;
        std::cerr << "Example: " << argv[0]
                  << " 192.168.1.100 9999 0 0x12345678 16777216 100"
                  << std::endl;
        return EXIT_FAILURE;
    }

    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int worker_id = std::atoi(argv[3]);
    uint32_t session_id = static_cast<uint32_t>(std::stoul(argv[4], nullptr, 16));
    size_t num_floats = static_cast<size_t>(std::atoi(argv[5]));
    int iterations = std::atoi(argv[6]);

    // Validate input
    if (num_floats == 0 || iterations == 0) {
        std::cerr << "[ERROR] num_floats and iterations must be > 0" << std::endl;
        return EXIT_FAILURE;
    }

    std::cout << "=== CPU Utilization Benchmark ===" << std::endl;
    std::cout << " Aggregator: " << ip << ":" << port << std::endl;
    std::cout << " Worker ID:  " << worker_id << std::endl;
    std::cout << " Session ID: 0x" << std::hex << session_id << std::dec << std::endl;
    std::cout << " Tensor Size: " << num_floats << " floats ("
              << (num_floats * sizeof(float)) / (1024.0 * 1024.0) << " MB)" << std::endl;
    std::cout << " Iterations:  " << iterations << std::endl;

    // --- 2. Initialize the eBPF client ---
    if (switchml_init(ip, port, worker_id, session_id) != 0) {
        std::cerr << "[ERROR] Failed to initialize switchml client" << std::endl;
        return EXIT_FAILURE;
    }

    // --- 3. Prepare buffers ---
    std::vector<float> sendbuf(num_floats, 1.0f);
    std::vector<float> recvbuf(num_floats, 0.0f);

    // --- 4. Warm-up (to avoid cold-start cache effects) ---
    std::cout << " Warming up..." << std::endl;
    for (int i = 0; i < 10; ++i) {
        if (switchml_allreduce(sendbuf.data(), recvbuf.data(), num_floats) != 0) {
            std::cerr << "[WARN] Warm-up iteration " << i << " failed" << std::endl;
        }
    }

    // --- 5. Measure CPU usage ---
    // Force a context switch / wait for stable state
    std::this_thread::sleep_for(std::chrono::milliseconds(10));

    CpuTime cpu_start = read_cpu_time();
    auto wall_start = std::chrono::steady_clock::now();

    // Run the benchmark
    int successful_iters = 0;
    for (int i = 0; i < iterations; ++i) {
        if (switchml_allreduce(sendbuf.data(), recvbuf.data(), num_floats) == 0) {
            successful_iters++;
        } else {
            std::cerr << "[WARN] Iteration " << i << " failed" << std::endl;
        }
    }

    auto wall_end = std::chrono::steady_clock::now();
    CpuTime cpu_end = read_cpu_time();

    // --- 6. Compute results ---
    double wall_time_sec = std::chrono::duration<double>(wall_end - wall_start).count();
    unsigned long long cpu_total_diff = cpu_end.total() - cpu_start.total();
    unsigned long long cpu_idle_diff = (cpu_end.idle + cpu_end.iowait) -
                                       (cpu_start.idle + cpu_start.iowait);

    double cpu_usage_percent = 100.0;
    if (cpu_total_diff > 0) {
        cpu_usage_percent = 100.0 * (1.0 - (static_cast<double>(cpu_idle_diff) /
                                            static_cast<double>(cpu_total_diff)));
    }

    // --- 7. Print results (CSV-friendly) ---
    std::cout << "\n=== RESULTS ===" << std::endl;
    std::cout << "Successful iterations: " << successful_iters << "/" << iterations << std::endl;
    std::cout << "Wall time:            " << std::fixed << std::setprecision(3)
              << wall_time_sec << " s" << std::endl;
    std::cout << "Avg iteration time:   " << std::setprecision(1)
              << (wall_time_sec * 1e6 / successful_iters) << " µs" << std::endl;

    // This is the KEY METRIC for your PhD graph
    std::cout << "CPU Utilization:      " << std::setprecision(2) << cpu_usage_percent << " %" << std::endl;

    // Also output as CSV for easy scripting
    std::cout << "\n[CSV] " << worker_id << ","
              << (num_floats * sizeof(float)) / (1024.0 * 1024.0) << ","
              << (wall_time_sec * 1e6 / successful_iters) << ","
              << cpu_usage_percent << std::endl;

    // --- 8. Cleanup ---
    switchml_finalize();

    // Return non-zero if too many failures
    return (successful_iters >= iterations * 0.9) ? EXIT_SUCCESS : EXIT_FAILURE;
}