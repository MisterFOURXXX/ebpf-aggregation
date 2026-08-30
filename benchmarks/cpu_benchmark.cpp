#include "switchml.h"
#include <iostream>
#include <vector>
#include <fstream>
#include <chrono>
#include <thread>
#include <iomanip>
#include <cstdlib>

struct CpuTime {
    unsigned long long user, nice, system, idle, iowait, irq, softirq, steal;
    unsigned long long total() const {
        return user + nice + system + idle + iowait + irq + softirq + steal;
    }
};

CpuTime read_cpu_time() {
    std::ifstream stat("/proc/stat");
    if (!stat.is_open()) { std::cerr << "Cannot open /proc/stat\n"; exit(1); }
    std::string line;
    std::getline(stat, line);
    CpuTime t{};
    sscanf(line.c_str(), "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
           &t.user, &t.nice, &t.system, &t.idle, &t.iowait, &t.irq, &t.softirq, &t.steal);
    return t;
}

int main(int argc, char** argv) {
    if (argc < 6) { /* usage */ return 1; }
    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int wid = std::atoi(argv[3]);
    size_t num_ints = static_cast<size_t>(std::atoi(argv[4]));
    int iters = std::atoi(argv[5]);

    if (switchml_init(ip, port, wid) < 0) { std::cerr << "Init failed\n"; return 1; }
    std::vector<int32_t> sendbuf(num_ints, 1);
    std::vector<int32_t> recvbuf(num_ints, 0);

    for (int i = 0; i < 10; ++i)
        switchml_allreduce(sendbuf.data(), recvbuf.data(), num_ints);

    CpuTime start_cpu = read_cpu_time();
    auto wall_start = std::chrono::steady_clock::now();

    int successful = 0;
    for (int i = 0; i < iters; ++i)
        if (switchml_allreduce(sendbuf.data(), recvbuf.data(), num_ints) == 0)
            ++successful;

    auto wall_end = std::chrono::steady_clock::now();
    CpuTime end_cpu = read_cpu_time();

    double wall_time = std::chrono::duration<double>(wall_end - wall_start).count();
    unsigned long long total_diff = end_cpu.total() - start_cpu.total();
    unsigned long long idle_diff = (end_cpu.idle + end_cpu.iowait) -
                                   (start_cpu.idle + start_cpu.iowait);
    double cpu_usage = 100.0 * (1.0 - (double)idle_diff / total_diff);

    std::cout << std::fixed << std::setprecision(2);
    std::cout << "Successful: " << successful << "/" << iters << "\n";
    std::cout << "Wall time: " << wall_time << " s\n";
    std::cout << "Avg iter time: " << (wall_time * 1e6 / successful) << " µs\n";
    std::cout << "CPU Utilization: " << cpu_usage << " %\n";

    switchml_finalize();
    return 0;
}