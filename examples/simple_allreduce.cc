// simple_allreduce.cc - Test 2 workers
#include "switchml.h"
#include <iostream>
#include <vector>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "Usage: ./simple_allreduce <ip> <port> <worker_id>\n";
        return 1;
    }
    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int wid = std::atoi(argv[3]);

    if (switchml_init(ip, port, wid) < 0) {
        std::cerr << "Init failed\n";
        return 1;
    }

    const size_t N = 64;
    std::vector<float> sendbuf(N, wid + 1.0f);  // Worker 1 sends 1.0, Worker 2 sends 2.0...
    std::vector<float> recvbuf(N, 0.0f);

    if (switchml_allreduce(sendbuf.data(), recvbuf.data(), N) < 0) {
        std::cerr << "AllReduce failed\n";
        return 1;
    }

    // Expected: (N_workers * (N_workers+1))/2 = e.g., for 2 workers: 1+2=3
    std::cout << "Worker " << wid << " result[0] = " << recvbuf[0] << " (expected sum of workers)\n";
    switchml_finalize();
    return 0;
}