#include "chunker.h"
#include <cassert>
#include <iostream>
#include <vector>

// Dynamic verification: works regardless of MAX_INTS_PER_PKT value.
static void verify(size_t total) {
    auto chunks = split_tensor(total);

    // 1. Concatenation of chunks must equal total
    size_t sum = 0;
    for (const auto& c : chunks) sum += c.num_ints;
    assert(sum == total);

    // 2. No chunk may exceed MAX_INTS_PER_PKT
    for (const auto& c : chunks) {
        assert(c.num_ints > 0);
        assert(c.num_ints <= MAX_INTS_PER_PKT);
    }

    // 3. Offsets must be contiguous
    size_t expected_off = 0;
    for (const auto& c : chunks) {
        assert(c.offset == expected_off);
        expected_off += c.num_ints;
    }

    // 4. If total > 0, last chunk is the remainder
    if (total > 0) {
        assert(chunks.back().offset + chunks.back().num_ints == total);
    }
}

int main() {
    // Exercise many sizes including boundaries
    std::vector<size_t> sizes = {0, 1, 2, 63, 64, 65, 127, 128, 129, 200, 1000, 4096};
    for (size_t s : sizes) verify(s);

    std::cout << "All chunker tests passed (MAX_INTS_PER_PKT=" << MAX_INTS_PER_PKT << ")\n";
    return 0;
}
