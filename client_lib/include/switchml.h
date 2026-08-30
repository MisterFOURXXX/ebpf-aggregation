#ifndef SWITCHML_H
#define SWITCHML_H

#include <cstddef>
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

int switchml_init(const char* ip, int port, int wid);
int switchml_allreduce(const int32_t* sendbuf, int32_t* recvbuf, size_t count);
void switchml_reset_seq(uint32_t new_seq);
int switchml_finalize();

#ifdef __cplusplus
}
#endif

// This struct must be packed and match the eBPF definition.
// All fields are in HOST byte order (little-endian on x86).
struct gradient_hdr {
    uint32_t session_id;
    uint32_t seq_num;
    uint16_t worker_id;
    uint16_t payload_ints;
} __attribute__((packed));

#endif