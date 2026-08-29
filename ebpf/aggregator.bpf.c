// aggregator.bpf.c - Main XDP program
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include "aggregator.h"

char LICENSE[] SEC("license") = "GPL";

// 1. BPF Map: Accumulation storage
// Key = (session_id << 32) | seq_num
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1000000);
    __uint(key_size, sizeof(__u64));
    __uint(value_size, sizeof(struct agg_value));
} agg_map SEC(".maps");

// 2. BPF Map: Configuration (expected workers per session)
struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_HASH);
    __uint(max_entries, 1000000);
    __uint(key_size, sizeof(__u64));   // session_id << 32 | seq_num
    __uint(value_size, sizeof(struct agg_value));
} agg_map SEC(".maps");

// 3. XDP Entry Point
SEC("xdp")
int gradient_aggregator(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;

    // Parse Ethernet, IP, UDP headers
    struct ethhdr *eth = data;
    struct iphdr *ip = (void *)(eth + 1);
    struct udphdr *udp = (void *)(ip + 1);
    struct gradient_hdr *hdr = (void *)(udp + 1);

    // Bounds check
    if ((void *)(hdr + 1) > data_end)
        return XDP_PASS;  // Not our packet

    // Validate UDP destination port (optional)
    // if (udp->dest != bpf_htons(9999)) return XDP_PASS;

    // 4. Read expected worker count for this session
    __u32 *expected = bpf_map_lookup_elem(&config_map, &hdr->session_id);
    if (!expected) return XDP_DROP;  // Session not configured

    // 5. Compute map key: (session_id << 32) | seq_num
    __u64 map_key = ((__u64)hdr->session_id << 32) | hdr->seq_num;
    struct agg_value *val = bpf_map_lookup_elem(&agg_map, &map_key);

    if (!val) {
        // Initialize new aggregation entry
        struct agg_value new_val = { .arrived_mask = 0 };
        #pragma unroll
        for (int i = 0; i < PAYLOAD_FLOATS; i++) {
            new_val.sum[i] = 0.0f;
        }
        bpf_map_update_elem(&agg_map, &map_key, &new_val, BPF_NOEXIST);
        val = bpf_map_lookup_elem(&agg_map, &map_key);
        if (!val) return XDP_DROP;
    }

    // 6. Accumulate the gradient payload (element-wise addition)
    float *payload = (float *)(hdr + 1);
    __u16 count = hdr->payload_floats;
    if (count > PAYLOAD_FLOATS) count = PAYLOAD_FLOATS;

    #pragma unroll
    for (int i = 0; i < PAYLOAD_FLOATS; i++) {
        if (i < count) {
            val->sum[i] += payload[i];
        }
    }

    // 7. Update arrival mask
    __u32 mask_bit = 1 << hdr->worker_id;
    val->arrived_mask |= mask_bit;

    // 8. Check completion
    __u32 expected_mask = (1 << *expected) - 1;
    if (val->arrived_mask == expected_mask) {
        // Aggregation complete! Prepare reply packet.
        // We swap MACs and send the accumulated sum back to the worker.

        // Overwrite the packet payload with the aggregated sum
        float *reply_payload = (float *)(hdr + 1);
        #pragma unroll
        for (int i = 0; i < PAYLOAD_FLOATS; i++) {
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

    // Not complete: drop the original packet (we have the data in the map)
    return XDP_DROP;
}