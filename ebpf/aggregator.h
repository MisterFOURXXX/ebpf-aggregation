#ifndef __AGGREGATOR_H
#define __AGGREGATOR_H

#include <linux/types.h>

struct gradient_hdr {
    __u32 session_id;
    __u32 seq_num;
    __u16 worker_id;
    __u16 payload_count;        // number of int32 values
} __attribute__((packed));

struct agg_value {
    __s32 sum[32];              // fixed‑point sums (scaled)
    __u64 mask;
};

#endif