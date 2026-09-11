#include <unistd.h>
#include <unistd.h>
/*
 * Measure CPU time of the AGGREGATOR process only.
 * Usage: cpu_benchmark <ip> <port> <wid> <aggregator-pid>
 */
#include "switchml.h"
#include <iostream>
#include <vector>
#include <chrono>
#include <fstream>
#include <cstdlib>
#include <unistd.h>
#include <cstdio>

static double read_proc_cpu(int pid) {
    std::ifstream f("/proc/" + std::to_string(pid) + "/stat");
    if (!f) return -1;
    std::string line; std::getline(f, line);
    size_t p = line.rfind(')');
    if (p == std::string::npos) return -1;
    std::string rest = line.substr(p + 2);
    long utime = 0, stime = 0;
    std::sscanf(rest.c_str(),
        "%*c %*d %*d %*d %*d %*d %*u %*u %*u %*u %*u %*u %ld %ld",
        &utime, &stime);
    long ticks = sysconf(_SC_CLK_TCK);
    return (utime + stime) / (double)ticks;
}

int main(int argc, char** argv) {
    if (argc < 5) {
        std::cerr << "Usage: cpu_benchmark <ip> <port> <wid> <aggregator-pid>\n";
        return 1;
    }
    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int wid  = std::atoi(argv[3]);
    int agg_pid = std::atoi(argv[4]);

    // sanity check
    if (read_proc_cpu(agg_pid) < 0) {
        std::cerr << "ERROR: cannot read /proc/" << agg_pid << "/stat — bad PID?\n";
        return 2;
    }

    size_t n = 64 * 1024 / sizeof(float);
    int iters = 50;

    if (switchml_init(ip, port, wid, 0xCAFE) != 0) {
        std::cerr << "switchml_init failed\n"; return 3;
    }
    std::vector<float> s(n, 1.0f), r(n, 0.0f);
    for (int i = 0; i < 5; i++) switchml_allreduce(s.data(), r.data(), n);

    double c0 = read_proc_cpu(agg_pid);
    auto w0 = std::chrono::steady_clock::now();

    int ok = 0;
    for (int i = 0; i < iters; i++)
        if (switchml_allreduce(s.data(), r.data(), n) == 0) ok++;

    auto w1 = std::chrono::steady_clock::now();
    double c1 = read_proc_cpu(agg_pid);

    double wall = std::chrono::duration<double>(w1 - w0).count();
    double cpu  = c1 - c0;
    double pct  = (wall > 0) ? 100.0 * cpu / wall : 0.0;

    std::cout << "Aggregator CPU time:  " << cpu  << " s\n";
    std::cout << "Wall time:            " << wall << " s\n";
    std::cout << "CPU Utilization:      " << pct  << " %  (of 1 core)\n";
    std::cout << "Iterations OK:        " << ok << " / " << iters << "\n";
    switchml_finalize();
    return (ok == iters) ? 0 : 4;
}
