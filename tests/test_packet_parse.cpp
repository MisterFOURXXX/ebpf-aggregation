#include <cstdint>
#include <cassert>
#include <iostream>

struct __attribute__((packed)) gradient_hdr {
    uint32_t session_id;
    uint32_t seq_num;
    uint16_t worker_id;
    uint16_t payload_count;
};

int main() {
    assert(sizeof(gradient_hdr) == 12);
    assert(offsetof(gradient_hdr, session_id) == 0);
    assert(offsetof(gradient_hdr, seq_num) == 4);
    assert(offsetof(gradient_hdr, worker_id) == 8);
    assert(offsetof(gradient_hdr, payload_count) == 10);
    std::cout << "Packet parse test passed\n";
    return 0;
}