// test_packet_parse.cpp - Validate packet structure matches eBPF
#include <cstring>
#include <cassert>

struct gradient_hdr {
    uint32_t session_id;
    uint32_t seq_num;
    uint16_t worker_id;
    uint16_t payload_floats;
};

int main() {
    // Ensure struct is packed correctly (no padding)
    assert(sizeof(gradient_hdr) == 12);
    assert(offsetof(gradient_hdr, session_id) == 0);
    assert(offsetof(gradient_hdr, seq_num) == 4);
    assert(offsetof(gradient_hdr, worker_id) == 8);
    assert(offsetof(gradient_hdr, payload_floats) == 10);
    
    std::cout << "Packet structure matches eBPF! (size=" << sizeof(gradient_hdr) << ")\n";
    return 0;
}