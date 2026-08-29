// switchml.cpp - C++ Wrapper for the C API
#include "switchml.h"
#include <iostream>
#include <mutex>
#include <stdexcept>

// Forward declarations from udp_client.cpp
extern "C" {
    int switchml_init(const char*, int, int, uint32_t);
    int switchml_allreduce(const float*, float*, size_t);
    int switchml_finalize();
}

namespace switchml {

class Session {
public:
    Session(const std::string& ip, int port, int wid, uint32_t sid) {
        if (switchml_init(ip.c_str(), port, wid, sid) != 0) {
            throw std::runtime_error("Failed to initialize eBPF-Agg session");
        }
        std::cout << "[C++] eBPF-Agg session established (ID: 0x"
                  << std::hex << sid << std::dec << ")" << std::endl;
    }
    ~Session() {
        switchml_finalize();
    }

    int allreduce(const float* send, float* recv, size_t count) {
        return switchml_allreduce(send, recv, count);
    }
};

// Convenience function for C++ users
int allreduce(const float* sendbuf, float* recvbuf, size_t count) {
    return switchml_allreduce(sendbuf, recvbuf, count);
}

} // namespace switchml