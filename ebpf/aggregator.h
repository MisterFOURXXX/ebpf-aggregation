#ifndef __AGGREGATOR_H
#define __AGGREGATOR_H

#define MAX_WORKERS 16
#define PAYLOAD_INTS 32
#define MAX_SESSIONS 1024

struct gradient_hdr {
    __u32 session_id;
    __u32 seq_num;
    __u16 worker_id;
    __u16 payload_ints;
};

// Only sums – mask is stored in a separate array
struct agg_value {
    __s32 sum[PAYLOAD_INTS];
};

#endif