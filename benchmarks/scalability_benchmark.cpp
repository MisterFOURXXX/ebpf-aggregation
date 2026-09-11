/*
 * Scalability: N forked workers -> one aggregator with NUM_WORKERS=N.
 * Usage: scalability_benchmark <ip> <port> <N>
 * Output: one CSV row per worker: N,worker_id,latency_us,ok
 */
#include "switchml.h"
#include <iostream>
#include <vector>
#include <chrono>
#include <sys/wait.h>
#include <unistd.h>
#include <cstdlib>
#include <cstring>
#include <cstdio>

static const size_t FLOATS = 256;
static const int    ITERS  = 10;

static void worker(const char* ip, int port, int wid, int write_fd) {
    if (switchml_init(ip, port, wid, 0x1234) != 0) _exit(2);
    std::vector<float> s(FLOATS, 1.0f), r(FLOATS, 0.0f);

    for (int i = 0; i < 3; i++) switchml_allreduce(s.data(), r.data(), FLOATS);

    auto t0 = std::chrono::high_resolution_clock::now();
    int ok = 0;
    for (int i = 0; i < ITERS; i++)
        if (switchml_allreduce(s.data(), r.data(), FLOATS) == 0) ok++;
    auto t1 = std::chrono::high_resolution_clock::now();

    long us = std::chrono::duration_cast<std::chrono::microseconds>(t1 - t0).count() / ITERS;
    char buf[64];
    int n = snprintf(buf, sizeof(buf), "%d,%ld,%d\n", wid, us, ok);
    (void)write(write_fd, buf, n);
    close(write_fd);
    switchml_finalize();
    _exit(0);
}

int main(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "Usage: scalability_benchmark <ip> <port> <N>\n";
        return 1;
    }
    const char* ip = argv[1];
    int port       = std::atoi(argv[2]);
    int N          = std::atoi(argv[3]);

    if (N < 1 || N > 64) { std::cerr << "N must be 1..64\n"; return 1; }

    int pipefd[2];
    if (pipe(pipefd) != 0) { perror("pipe"); return 1; }

    std::vector<pid_t> pids;
    for (int w = 0; w < N; w++) {
        pid_t p = fork();
        if (p == 0) {
            close(pipefd[0]);
            worker(ip, port, w, pipefd[1]);
        }
        pids.push_back(p);
    }
    close(pipefd[1]);

    std::string all;
    char tmp[256];
    ssize_t r;
    while ((r = read(pipefd[0], tmp, sizeof(tmp))) > 0)
        all.append(tmp, r);
    close(pipefd[0]);
    for (pid_t p : pids) { int st; waitpid(p, &st, 0); }

    char* line = strtok(&all[0], "\n");
    while (line) {
        int wid, ok; long us;
        if (sscanf(line, "%d,%ld,%d", &wid, &us, &ok) == 3)
            std::cout << N << "," << wid << "," << us << "," << ok << "\n";
        line = strtok(nullptr, "\n");
    }
    return 0;
}
