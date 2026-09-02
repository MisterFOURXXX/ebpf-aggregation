#include "../include/switchml.h"
#include <iostream>
#include <mutex>

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
                throw std::runtime_error("Failed to init SwitchML session");
            }
        }
        ~Session() { switchml_finalize(); }
        int allreduce(const float* send, float* recv, size_t count) {
            return switchml_allreduce(send, recv, count);
        }
    };
}