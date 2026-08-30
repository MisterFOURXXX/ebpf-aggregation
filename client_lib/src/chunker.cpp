// chunker.cpp - Splits large tensors into MTU-friendly packets
#include <cstring>
#include <vector>
#include <algorithm>
#include <cstdint>
#include <cstddef>

#define MAX_FLOATS_PER_PKT 32

struct Chunk {
    size_t offset;      // Starting index in the original tensor
    size_t num_floats;  // Number of floats in this chunk
};

std::vector<Chunk> split_tensor(size_t total_floats) {
    std::vector<Chunk> chunks;
    size_t offset = 0;
    while (offset < total_floats) {
        size_t remaining = total_floats - offset;
        size_t chunk_size = std::min(remaining, static_cast<size_t>(MAX_FLOATS_PER_PKT));
        chunks.push_back({offset, chunk_size});
        offset += chunk_size;
    }
    return chunks;
}

// Helper to pack a chunk safely into a byte buffer using struct placement
void pack_chunk(const float* src, size_t offset, size_t count, 
                uint8_t* dst, uint32_t session_id, uint32_t seq, uint16_t worker_id) {
    struct gradient_hdr {
        uint32_t session_id;
        uint32_t seq_num;
        uint16_t worker_id;
        uint16_t payload_floats;
    } __attribute__((packed));

    auto* hdr = reinterpret_cast<gradient_hdr*>(dst);
    hdr->session_id = session_id;
    hdr->seq_num = seq;
    hdr->worker_id = worker_id;
    hdr->payload_floats = static_cast<uint16_t>(count);

    float* p_data = reinterpret_cast<float*>(dst + sizeof(gradient_hdr));
    std::memcpy(p_data, src + offset, count * sizeof(float));
}