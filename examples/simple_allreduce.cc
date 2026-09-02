#include "switchml.h"
#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 4) { std::cerr << "Usage: simple_allreduce <ip> <port> <worker_id>\n"; return 1; }
    const char* ip = argv[1];
    int port = std::atoi(argv[2]);
    int wid = std::atoi(argv[3]);

    if (switchml_init(ip, port, wid, 0xABCD) != 0) {
        std::cerr << "Init failed\n";
        return 1;
    }
    const size_t N = 1024;
    std::vector<float> send(N, 1.0f), recv(N, 0.0f);
    if (switchml_allreduce(send.data(), recv.data(), N) == 0) {
        std::cout << "AllReduce succeeded. First result: " << recv[0] << "\n";
    } else {
        std::cerr << "AllReduce failed\n";
    }
    switchml_finalize();
    return 0;
}