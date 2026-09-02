#include "switchml.h"
#include <iostream>
#include <vector>
#include <fstream>
#include <chrono>
#include <thread>
#include <cmath>

struct CpuTime {
    unsigned long long user, nice, system, idle, iowait, irq, softirq, steal;
    unsigned long long total() const {
        return user + nice + system + idle + iowait + irq + softirq + steal;
    }
};

CpuTime read_cpu_time() {
    std::ifstream stat("/proc/stat");
    std::string line;
    getline(stat, line);
    CpuTime t;
    sscanf(line.c_str(), "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
           &t.user, &t.nice, &t.system, &t.idle, &t.iowait, &t.irq, &t.softirq, &t.steal);
    return t;
}

int main(int argc, char** argv) {
    if (argc < 4) { std::cerr << "Usage: cpu_benchmark <ip> <port> <worker_id>\n"; return 1; }
    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int wid = std::atoi(argv[3]);
    size_t num_floats = 64 * 1024 * 1024 / 4; // 64MB
    int iters = 100;

    switchml_init(ip, port, wid, 0x1234);
    std::vector<float> sendbuf(num_floats, 1.0f);
    std::vector<float> recvbuf(num_floats, 0.0f);

    CpuTime start = read_cpu_time();
    auto wall_start = std::chrono::steady_clock::now();

    for (int i = 0; i < iters; i++) {
        switchml_allreduce(sendbuf.data(), recvbuf.data(), num_floats);
    }

    auto wall_end = std::chrono::steady_clock::now();
    CpuTime end = read_cpu_time();

    double wall_time = std::chrono::duration<double>(wall_end - wall_start).count();
    unsigned long long total_diff = end.total() - start.total();
    unsigned long long idle_diff = (end.idle + end.iowait) - (start.idle + start.iowait);
    double cpu_usage = 100.0 * (1.0 - ((double)idle_diff / total_diff));

    std::cout << "CPU Utilization: " << cpu_usage << " %\n";
    switchml_finalize();
    return 0;
}