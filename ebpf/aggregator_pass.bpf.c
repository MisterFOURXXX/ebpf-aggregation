// SPDX-License-Identifier: GPL-2.0
/*
 * Aggregator variant that returns XDP_PASS for all packets.
 * Used for ablation A3 - forces replies through the kernel stack
 * instead of the XDP_TX fast-path.
 */
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/in.h>
#include <linux/udp.h>
#include <linux/types.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include "aggregator.h"
#include "maps_config.h"

char LICENSE[] SEC("license") = "GPL";

struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_HASH);
    __uint(max_entries, 1000000);
    __uint(key_size, sizeof(__u64));
    __uint(value_size, sizeof(struct agg_value));
} agg_map SEC(".maps");

SEC("xdp")
int xdp_aggregator_pass(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data     = (void *)(long)ctx->data;

    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return XDP_PASS;
    if (eth->h_proto != bpf_htons(ETH_P_IP)) return XDP_PASS;

    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end) return XDP_PASS;
    if (ip->protocol != IPPROTO_UDP) return XDP_PASS;

    struct udphdr *udp = (void *)(ip + 1);
    if ((void *)(udp + 1) > data_end) return XDP_PASS;

    struct gradient_hdr *hdr = (void *)(udp + 1);
    if ((void *)(hdr + 1) > data_end) return XDP_PASS;

    __u32 sid = hdr->session_id;
    __u32 sq  = hdr->seq_num;
    __u16 wid = hdr->worker_id;
    __u16 pc  = hdr->payload_count;
    if (pc > PAYLOAD_FLOATS) return XDP_PASS;

    __u8 *payload_base = (__u8 *)(hdr + 1);
    if (payload_base + PAYLOAD_FLOATS * (int)sizeof(__s32) > (__u8 *)data_end)
        return XDP_PASS;

    __u64 key = ((__u64)sid << 32) | sq;

    struct agg_value *val = bpf_map_lookup_elem(&agg_map, &key);
    if (!val) {
        struct agg_value nv = {0};
        if (bpf_map_update_elem(&agg_map, &key, &nv, BPF_NOEXIST) < 0)
            return XDP_PASS;
        val = bpf_map_lookup_elem(&agg_map, &key);
        if (!val) return XDP_PASS;
    }

    /* Fully-unrolled aggregation (verifier-safe) */
    #define AGG_ONE(I) do { \
        if ((I) < pc) { \
            __u8 *p = payload_base + (I) * 4; \
            if (p + 4 <= (__u8 *)data_end) { \
                __s32 v = *(__s32 *)p; \
                val->sum[(I)] += v; \
            } \
        } \
    } while (0)

    AGG_ONE(0);  AGG_ONE(1);  AGG_ONE(2);  AGG_ONE(3);
    AGG_ONE(4);  AGG_ONE(5);  AGG_ONE(6);  AGG_ONE(7);
    AGG_ONE(8);  AGG_ONE(9);  AGG_ONE(10); AGG_ONE(11);
    AGG_ONE(12); AGG_ONE(13); AGG_ONE(14); AGG_ONE(15);
    AGG_ONE(16); AGG_ONE(17); AGG_ONE(18); AGG_ONE(19);
    AGG_ONE(20); AGG_ONE(21); AGG_ONE(22); AGG_ONE(23);
    AGG_ONE(24); AGG_ONE(25); AGG_ONE(26); AGG_ONE(27);
    AGG_ONE(28); AGG_ONE(29); AGG_ONE(30); AGG_ONE(31);
    #undef AGG_ONE

    val->mask |= (1ULL << wid);

    /* Always XDP_PASS - reply goes through kernel stack */
    return XDP_PASS;
}
