#include "chunker.h"
#include <cassert>
#include <iostream>

int main() {
    // With MAX_INTS_PER_PKT=16:
    // 100 ints should give 7 chunks: 16*6 + 4 = 100
    auto chunks = split_tensor(100);
    assert(chunks.size() == 7);
    for (int i = 0; i < 6; i++) {
        assert(chunks[i].num_ints == 16);
    }
    assert(chunks[6].num_ints == 4);
    assert(chunks[0].offset == 0);
    assert(chunks[1].offset == 16);
    assert(chunks[2].offset == 32);
    assert(chunks[3].offset == 48);
    assert(chunks[4].offset == 64);
    assert(chunks[5].offset == 80);
    assert(chunks[6].offset == 96);
    
    // Test 2: 32 ints should give 2 chunks: 16 + 16
    auto chunks2 = split_tensor(32);
    assert(chunks2.size() == 2);
    assert(chunks2[0].num_ints == 16);
    assert(chunks2[1].num_ints == 16);
    assert(chunks2[0].offset == 0);
    assert(chunks2[1].offset == 16);
    
    // Test 3: 16 ints should give 1 chunk
    auto chunks3 = split_tensor(16);
    assert(chunks3.size() == 1);
    assert(chunks3[0].num_ints == 16);
    assert(chunks3[0].offset == 0);
    
    std::cout << "All chunker tests passed!\n";
    return 0;
}
