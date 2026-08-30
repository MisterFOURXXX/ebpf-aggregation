#include "switchml.h"
#include <iostream>
#include <vector>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "Usage: ./simple_allreduce <ip> <port> <worker_id>\n";
        return 1;
    }
    const char* ip = argv[1];          // always 192.168.1.100 for the aggregator
    int port = std::atoi(argv[2]);     // 9999
    int wid = std::atoi(argv[3]);      // 0..3

    if (switchml_init(ip, port, wid) < 0) {
        std::cerr << "Init failed\n";
        return 1;
    }
    const size_t N = 32;
    std::vector<int32_t> sendbuf(N, wid + 1);
    std::vector<int32_t> recvbuf(N, 0);
    if (switchml_allreduce(sendbuf.data(), recvbuf.data(), N) < 0) {
        std::cerr << "AllReduce failed\n";
        return 1;
    }
    std::cout << "Worker " << wid << " result[0] = " << recvbuf[0] << "\n";
    switchml_finalize();
    return 0;
}