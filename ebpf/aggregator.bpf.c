// aggregator.bpf.c - Self-contained XDP aggregator (integer version)
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include "aggregator.h"

char LICENSE[] SEC("license") = "GPL";

// ============================================================
// Custom network header definitions (avoid kernel header dependencies)
// ============================================================
struct ethhdr_custom {
    unsigned char h_dest[6];
    unsigned char h_source[6];
    __be16        h_proto;
};

struct iphdr_custom {
    __u8  ihl:4, version:4;
    __u8  tos;
    __be16 tot_len;
    __be16 id;
    __be16 frag_off;
    __u8  ttl;
    __u8  protocol;
    __be16 check;
    __be32 saddr;
    __be32 daddr;
};

struct udphdr_custom {
    __be16 source;
    __be16 dest;
    __be16 len;
    __be16 check;
};

// ============================================================
// BPF Maps
// ============================================================

// Aggregation storage (PERCPU_HASH for lock‑free performance)
struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_HASH);
    __uint(max_entries, 1000000);
    __uint(key_size, sizeof(__u64));             // (session_id << 32) | seq_num
    __uint(value_size, sizeof(struct agg_value));
} agg_map SEC(".maps");

// Configuration: expected worker count per session
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_SESSIONS);
    __uint(key_size, sizeof(__u32));             // session_id
    __uint(value_size, sizeof(__u32));           // expected_worker_count
} config_map SEC(".maps");

// ============================================================
// XDP Entry Point
// ============================================================
SEC("xdp")
int gradient_aggregator(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;

    // Parse headers using custom structs
    struct ethhdr_custom *eth = data;
    struct iphdr_custom  *ip  = (void *)(eth + 1);
    struct udphdr_custom *udp = (void *)(ip + 1);
    struct gradient_hdr  *hdr = (void *)(udp + 1);

    // Bounds check
    if ((void *)(hdr + 1) > data_end)
        return XDP_PASS;

    // Optional: filter by UDP destination port (9999)
    // if (udp->dest != bpf_htons(9999)) return XDP_PASS;

    // Read expected worker count for this session
    __u32 *expected = bpf_map_lookup_elem(&config_map, &hdr->session_id);
    if (!expected)
        return XDP_DROP;

    // Compute map key: (session_id << 32) | seq_num
    __u64 map_key = ((__u64)hdr->session_id << 32) | hdr->seq_num;
    struct agg_value *val = bpf_map_lookup_elem(&agg_map, &map_key);

    if (!val) {
        struct agg_value new_val = { .arrived_mask = 0 };
        #pragma unroll
        for (int i = 0; i < PAYLOAD_INTS; i++) {
            new_val.sum[i] = 0;
        }
        bpf_map_update_elem(&agg_map, &map_key, &new_val, BPF_NOEXIST);
        val = bpf_map_lookup_elem(&agg_map, &map_key);
        if (!val) return XDP_DROP;
    }

    // Accumulate payload as 64‑bit integers
    __s64 *payload = (__s64 *)(hdr + 1);
    __u16 count = hdr->payload_ints;
    if (count > PAYLOAD_INTS) count = PAYLOAD_INTS;

    #pragma unroll
    for (int i = 0; i < PAYLOAD_INTS; i++) {
        if (i < count) {
            val->sum[i] += payload[i];
        }
    }

    // Update arrival mask
    __u32 mask_bit = 1 << hdr->worker_id;
    val->arrived_mask |= mask_bit;

    // Check completion
    __u32 expected_mask = (1 << *expected) - 1;
    if (val->arrived_mask == expected_mask) {
        // Write the aggregated sum back into the packet payload
        __s64 *reply_payload = (__s64 *)(hdr + 1);
        #pragma unroll
        for (int i = 0; i < PAYLOAD_INTS; i++) {
            if (i < count) {
                reply_payload[i] = val->sum[i];
            }
        }

        // Swap MAC addresses (return to sender)
        __u8 tmp_mac[6];
        __builtin_memcpy(tmp_mac, eth->h_dest, 6);
        __builtin_memcpy(eth->h_dest, eth->h_source, 6);
        __builtin_memcpy(eth->h_source, tmp_mac, 6);

        // Delete map entry to free memory
        bpf_map_delete_elem(&agg_map, &map_key);

        // Send packet back out the same NIC (bypass kernel stack)
        return XDP_TX;
    }

    return XDP_DROP;
}