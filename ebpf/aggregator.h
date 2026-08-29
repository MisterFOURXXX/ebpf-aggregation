#ifndef __AGGREGATOR_H
#define __AGGREGATOR_H

#define MAX_WORKERS 16
#define PAYLOAD_INTS 32      // 32 × 8 bytes = 256 bytes per packet
#define MAX_SESSIONS 1024

// Custom packet header (matches C++ client)
struct gradient_hdr {
    __u32 session_id;
    __u32 seq_num;
    __u16 worker_id;
    __u16 payload_ints;      // number of 64‑bit integers in payload
};

// Value stored in the BPF map: accumulated sum + arrival mask
struct agg_value {
    __s64 sum[PAYLOAD_INTS];   // integer accumulation
    __u32 arrived_mask;
};

#endif