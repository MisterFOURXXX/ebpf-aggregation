// test_chunker.cpp - Unit test for tensor splitting
#include <cassert>
#include <vector>
#include <iostream>

// Copy of chunker logic for testing
std::vector<size_t> get_chunk_sizes(size_t total, size_t max_per_chunk) {
    std::vector<size_t> sizes;
    size_t offset = 0;
    while (offset < total) {
        size_t rem = total - offset;
        sizes.push_back(rem < max_per_chunk ? rem : max_per_chunk);
        offset += sizes.back();
    }
    return sizes;
}

int main() {
    auto sizes = get_chunk_sizes(100, 32);
    assert(sizes.size() == 4);  // 32+32+32+4 = 100
    assert(sizes[0] == 32);
    assert(sizes[3] == 4);
    std::cout << "All chunker tests passed!\n";
    return 0;
}