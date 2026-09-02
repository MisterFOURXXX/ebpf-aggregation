#ifndef __CHUNKER_H
#define __CHUNKER_H

#include <cstddef>
#include <cstdint>
#include <vector>

#define MAX_INTS_PER_PKT 32

struct Chunk {
    size_t offset;
    size_t num_ints;
};

std::vector<Chunk> split_tensor(size_t total_ints);
void pack_chunk(const int32_t* src, size_t offset, size_t count,
                uint8_t* dst, uint32_t session_id, uint32_t seq, uint16_t worker_id);

#endif