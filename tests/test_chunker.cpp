#include <cassert>
#include <vector>
#include <iostream>

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
    assert(sizes.size() == 4);
    assert(sizes[0] == 32 && sizes[1] == 32 && sizes[2] == 32 && sizes[3] == 4);

    sizes = get_chunk_sizes(10, 32);
    assert(sizes.size() == 1 && sizes[0] == 10);

    sizes = get_chunk_sizes(0, 32);
    assert(sizes.empty());

    std::cout << "All chunker tests passed!\n";
    return 0;
}