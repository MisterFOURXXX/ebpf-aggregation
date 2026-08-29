// chunker.cpp - Splits large tensors into MTU-friendly packets
#include <cstring>
#include <vector>
#include <algorithm>

// Maximum floats per packet (must match eBPF PAYLOAD_FLOATS)
#define MAX_FLOATS_PER_PKT 32

struct Chunk {
    size_t offset;          // Starting index in the original tensor
    size_t num_floats;      // Number of floats in this chunk
};

std::vector<Chunk> split_tensor(size_t total_floats) {
    std::vector<Chunk> chunks;
    size_t offset = 0;
    while (offset < total_floats) {
        size_t remaining = total_floats - offset;
        size_t chunk_size = std::min(remaining, (size_t)MAX_FLOATS_PER_PKT);
        chunks.push_back({offset, chunk_size});
        offset += chunk_size;
    }
    return chunks;
}

// Helper to pack a chunk into a byte buffer (used by udp_client.cpp)
void pack_chunk(const float* src, size_t offset, size_t count, 
                uint8_t* dst, uint32_t session_id, uint32_t seq, uint16_t worker_id) {
    // Structure matches eBPF's gradient_hdr + payload
    // Format: [session_id(4)][seq_num(4)][worker_id(2)][payload_floats(2)][data]
    uint32_t* p_session = (uint32_t*)dst;
    uint32_t* p_seq = (uint32_t*)(dst + 4);
    uint16_t* p_worker = (uint16_t*)(dst + 8);
    uint16_t* p_count = (uint16_t*)(dst + 10);
    float* p_data = (float*)(dst + 12);

    *p_session = session_id;
    *p_seq = seq;
    *p_worker = worker_id;
    *p_count = (uint16_t)count;
    memcpy(p_data, src + offset, count * sizeof(float));
}