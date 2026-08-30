#include <cstring>
#include <cassert>
#include <iostream>

struct gradient_hdr {
    uint32_t session_id;
    uint32_t seq_num;
    uint16_t worker_id;
    uint16_t payload_ints;
} __attribute__((packed));

int main() {
    assert(sizeof(gradient_hdr) == 12);
    assert(offsetof(gradient_hdr, session_id) == 0);
    assert(offsetof(gradient_hdr, seq_num) == 4);
    assert(offsetof(gradient_hdr, worker_id) == 8);
    assert(offsetof(gradient_hdr, payload_ints) == 10);
    std::cout << "Packet structure matches eBPF! (size=" << sizeof(gradient_hdr) << ")\n";
    return 0;
}