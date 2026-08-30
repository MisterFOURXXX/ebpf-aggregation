#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/udp.h>
#include "aggregator.h"

// Debug macro – enabled by -DDEBUG
#ifdef DEBUG
#define debug_print(fmt, ...) bpf_printk(fmt, ##__VA_ARGS__)
#else
#define debug_print(fmt, ...)
#endif

char LICENSE[] SEC("license") = "GPL";

struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, 1);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(struct agg_value));
} scratch_map SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1000000);
    __uint(key_size, sizeof(__u64));
    __uint(value_size, sizeof(struct agg_value));
} agg_map SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 65536);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(__u64));
} mask_array SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_SESSIONS);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(__u32));
} config_map SEC(".maps");

SEC("xdp")
int gradient_aggregator(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;

    debug_print("XDP: packet received\n");

    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return XDP_PASS;

    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end) return XDP_PASS;

    if (ip->protocol != 17) return XDP_PASS;
    debug_print("XDP: UDP packet\n");

    struct udphdr *udp = (void *)(ip + 1);
    if ((void *)(udp + 1) > data_end) return XDP_PASS;

    struct gradient_hdr *hdr = (void *)(udp + 1);
    if ((void *)(hdr + 1) > data_end) return XDP_PASS;

    __u32 *expected = bpf_map_lookup_elem(&config_map, &hdr->session_id);
    if (!expected) {
        debug_print("XDP: config_map lookup failed for session %u\n", hdr->session_id);
        return XDP_DROP;
    }
    debug_print("XDP: expected workers = %u\n", *expected);

    __u64 map_key = ((__u64)hdr->session_id << 32) | hdr->seq_num;

    // ---- Sums ----
    struct agg_value *val = bpf_map_lookup_elem(&agg_map, &map_key);
    if (!val) {
        __u32 zero = 0;
        struct agg_value *init = bpf_map_lookup_elem(&scratch_map, &zero);
        if (!init) return XDP_DROP;

        #pragma unroll
        for (int i = 0; i < PAYLOAD_INTS; i++)
            init->sum[i] = 0;

        if (bpf_map_update_elem(&agg_map, &map_key, init, BPF_NOEXIST) < 0)
            return XDP_DROP;

        val = bpf_map_lookup_elem(&agg_map, &map_key);
        if (!val) return XDP_DROP;
    }

    __s32 *payload = (__s32 *)(hdr + 1);
    __u16 count = hdr->payload_ints;
    if (count > PAYLOAD_INTS) count = PAYLOAD_INTS;

    if ((void *)(payload + count) > data_end) return XDP_DROP;

    #pragma unroll
    for (int i = 0; i < PAYLOAD_INTS; i++) {
        if (i < count) {
            if ((void *)&payload[i + 1] <= data_end) {
                val->sum[i] += payload[i];
            }
        }
    }

    // ---- Mask (array) ----
    __u32 idx = hdr->seq_num & 0xFFFF;
    __u64 *mask_ptr = bpf_map_lookup_elem(&mask_array, &idx);
    if (!mask_ptr) {
        debug_print("XDP: mask_array lookup failed for idx %u\n", idx);
        return XDP_DROP;
    }

    __u64 mask_bit = 1ULL << (hdr->worker_id & 31);
    __u64 old_mask = __sync_fetch_and_or(mask_ptr, mask_bit);
    __u64 new_mask = old_mask | mask_bit;

    debug_print("XDP: worker %u, seq %u, old_mask %llu, new_mask %llu\n",
                hdr->worker_id, hdr->seq_num, old_mask, new_mask);

    __u32 expected_mask = (1ULL << (*expected & 31)) - 1;
    debug_print("XDP: expected_mask = %u\n", expected_mask);

    if (new_mask == expected_mask) {
        debug_print("XDP: All workers arrived, sending reply\n");
        // Build reply
        __s32 *reply_payload = (__s32 *)(hdr + 1);
        #pragma unroll
        for (int i = 0; i < PAYLOAD_INTS; i++) {
            if (i < count) {
                if ((void *)&reply_payload[i + 1] <= data_end) {
                    reply_payload[i] = val->sum[i];
                }
            }
        }

        // Swap MACs
        __u8 tmp_mac[6];
        __builtin_memcpy(tmp_mac, eth->h_dest, 6);
        __builtin_memcpy(eth->h_dest, eth->h_source, 6);
        __builtin_memcpy(eth->h_source, tmp_mac, 6);

        // Clean up
        bpf_map_delete_elem(&agg_map, &map_key);
        __u64 zero_mask = 0;
        bpf_map_update_elem(&mask_array, &idx, &zero_mask, BPF_ANY);

        return XDP_TX;
    }

    debug_print("XDP: not all workers yet, dropping packet\n");
    return XDP_DROP;
}