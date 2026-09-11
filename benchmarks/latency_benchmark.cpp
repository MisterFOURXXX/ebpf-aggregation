#include "switchml.h"
#include <iostream>
#include <vector>
#include <chrono>
#include <algorithm>
#include <numeric>
#include <cmath>

int main(int argc, char** argv) {
    const char* ip = (argc > 1) ? argv[1] : "127.0.0.1";
    int port       = (argc > 2) ? std::atoi(argv[2]) : 9999;
    int wid        = (argc > 3) ? std::atoi(argv[3]) : 0;

    std::vector<size_t> sizes = {64, 256, 1024, 4096, 16384, 65536, 262144, 1048576};
    const int WARMUP  = 10;     // discard first 10
    const int MEASURE = 30;     // keep 30 samples

    switchml_init(ip, port, wid, 0x1234);
    std::cout << "size_bytes,mean_us,median_us,p95_us,trimmed_mean_us\n";

    for (auto bytes : sizes) {
        size_t n = bytes / sizeof(float);
        std::vector<float> s(n, 1.0f), r(n, 0.0f);

        // Warm-up
        for (int i = 0; i < WARMUP; i++)
            switchml_allreduce(s.data(), r.data(), n);

        std::vector<double> us;
        us.reserve(MEASURE);
        for (int i = 0; i < MEASURE; i++) {
            auto t0 = std::chrono::high_resolution_clock::now();
            if (switchml_allreduce(s.data(), r.data(), n) != 0) { us.clear(); break; }
            auto t1 = std::chrono::high_resolution_clock::now();
            us.push_back(std::chrono::duration<double, std::micro>(t1 - t0).count());
        }
        if (us.empty()) {
            std::cout << bytes << ",FAIL,FAIL,FAIL,FAIL\n" << std::flush;
            continue;
        }

        std::sort(us.begin(), us.end());
        double mean = std::accumulate(us.begin(), us.end(), 0.0) / us.size();
        double med  = us[us.size()/2];
        double p95  = us[(size_t)(us.size()*0.95)];

        // Trimmed mean: discard top and bottom 10%
        size_t lo = (size_t)(us.size() * 0.10);
        size_t hi = us.size() - lo;
        double tmean = std::accumulate(us.begin()+lo, us.begin()+hi, 0.0)
                       / (hi - lo);

        std::cout << bytes << "," << (int)mean << "," << (int)med
                  << "," << (int)p95 << "," << (int)tmean << "\n" << std::flush;
    }
    switchml_finalize();
    return 0;
}
