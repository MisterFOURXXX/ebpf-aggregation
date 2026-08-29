// aggregator.h
#ifndef __AGGREGATOR_H
#define __AGGREGATOR_H

#define MAX_WORKERS 16
#define PAYLOAD_FLOATS 32   // 32 floats * 4 bytes = 128 bytes payload
#define MAX_SESSIONS 1024

// Custom packet header (matches C++ client)
struct gradient_hdr {
    __u32 session_id;
    __u32 seq_num;          // Which chunk (0, 1, 2, ...)
    __u16 worker_id;
    __u16 payload_floats;   // Actual floats in payload (<= PAYLOAD_FLOATS)
};

// Value stored in the BPF map: accumulated sum + arrival mask
struct agg_value {
    float sum[PAYLOAD_FLOATS];   // Accumulated values (float is OK for BPF v3)
    __u32 arrived_mask;          // Bitmask of workers who sent
};

#endif