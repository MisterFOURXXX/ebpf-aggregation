#include "../include/chunker.h"
#include <cstring>
#include <algorithm>

std::vector<Chunk> split_tensor(size_t total_ints) {
    std::vector<Chunk> chunks;
    size_t offset = 0;
    while (offset < total_ints) {
        size_t remaining = total_ints - offset;
        size_t chunk_size = std::min(remaining, (size_t)MAX_INTS_PER_PKT);
        chunks.push_back({offset, chunk_size});
        offset += chunk_size;
    }
    return chunks;
}

void pack_chunk(const int32_t* src, size_t offset, size_t count,
                uint8_t* dst, uint32_t session_id, uint32_t seq, uint16_t worker_id) {
    uint32_t* p_session = (uint32_t*)dst;
    uint32_t* p_seq = (uint32_t*)(dst + 4);
    uint16_t* p_worker = (uint16_t*)(dst + 8);
    uint16_t* p_count = (uint16_t*)(dst + 10);
    int32_t* p_data = (int32_t*)(dst + 12);

    *p_session = session_id;
    *p_seq = seq;
    *p_worker = worker_id;
    *p_count = (uint16_t)count;
    memcpy(p_data, src + offset, count * sizeof(int32_t));
}
