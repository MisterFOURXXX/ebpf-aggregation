#include "chunker.h"
#include <cassert>
#include <iostream>

int main() {
    auto chunks = split_tensor(100);
    assert(chunks.size() == 4);
    assert(chunks[0].num_ints == 32);
    assert(chunks[1].num_ints == 32);
    assert(chunks[2].num_ints == 32);
    assert(chunks[3].num_ints == 4);
    assert(chunks[0].offset == 0);
    assert(chunks[1].offset == 32);
    assert(chunks[2].offset == 64);
    assert(chunks[3].offset == 96);
    std::cout << "Chunker test passed\n";
    return 0;
}