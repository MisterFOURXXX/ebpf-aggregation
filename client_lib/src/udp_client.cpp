#include "../include/switchml.h"
#include "../include/chunker.h"
#include <cstring>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <poll.h>
#include <vector>
#include <mutex>
#include <chrono>
#include <iostream>
#include <atomic>

static int sockfd = -1;
static struct sockaddr_in agg_addr;
static uint32_t session_id = 0;
static uint16_t worker_id = 0;
static std::atomic<bool> initialized{false};

struct Packet {
    uint8_t header[12];
    int32_t data[32];
};

extern "C" int switchml_init(const char* ip, int port, int wid, uint32_t sid) {
    if (initialized.exchange(true)) {
        switchml_finalize();
    }
    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) return -1;

    memset(&agg_addr, 0, sizeof(agg_addr));
    agg_addr.sin_family = AF_INET;
    agg_addr.sin_port = htons(port);
    if (inet_pton(AF_INET, ip, &agg_addr.sin_addr) <= 0) {
        close(sockfd);
        return -1;
    }
    worker_id = (uint16_t)wid;
    session_id = sid;
    return 0;
}

extern "C" int switchml_allreduce(const float* sendbuf, float* recvbuf, size_t count) {
    if (!initialized || sockfd < 0) return -1;

    const int SCALE = 1000;
    std::vector<int32_t> send_int(count);
    for (size_t i = 0; i < count; ++i) {
        send_int[i] = (int32_t)(sendbuf[i] * SCALE + 0.5f);
    }

    std::vector<Chunk> chunks = split_tensor(count);
    size_t num_packets = chunks.size();
    std::vector<Packet> packets(num_packets);

    for (size_t i = 0; i < num_packets; ++i) {
        auto& pkt = packets[i];
        pack_chunk(send_int.data(), chunks[i].offset, chunks[i].num_ints,
                   pkt.header, session_id, (uint32_t)i, worker_id);
        memcpy(pkt.data,
               send_int.data() + chunks[i].offset,
               chunks[i].num_ints * sizeof(int32_t));
    }

    for (size_t i = 0; i < num_packets; ++i) {
        size_t total_len = 12 + chunks[i].num_ints * sizeof(int32_t);
        if (sendto(sockfd, &packets[i], total_len, 0,
                   (struct sockaddr*)&agg_addr, sizeof(agg_addr)) < 0) {
            return -1;
        }
    }

    std::vector<int32_t> accum_ints(count, 0);
    std::vector<bool> received(num_packets, false);
    struct pollfd pfd = { .fd = sockfd, .events = POLLIN };
    int retries = 0;
    const int max_retries = 50;

    while (true) {
        bool all_done = true;
        for (bool r : received) if (!r) { all_done = false; break; }
        if (all_done) break;

        int ret = poll(&pfd, 1, 1);
        if (ret < 0) return -1;
        if (ret == 0) {
            retries++;
            if (retries > max_retries) return -1;
            continue;
        }

        Packet reply;
        struct sockaddr_in src;
        socklen_t src_len = sizeof(src);
        int n = recvfrom(sockfd, &reply, sizeof(Packet), MSG_DONTWAIT,
                         (struct sockaddr*)&src, &src_len);
        if (n < 12) continue;

        uint32_t r_session, r_seq;
        uint16_t r_worker, r_payload;
        memcpy(&r_session, reply.header, 4);
        memcpy(&r_seq, reply.header + 4, 4);
        memcpy(&r_worker, reply.header + 8, 2);
        memcpy(&r_payload, reply.header + 10, 2);

        if (r_session != session_id || r_seq >= num_packets) continue;

        if (!received[r_seq]) {
            size_t offset = chunks[r_seq].offset;
            memcpy(accum_ints.data() + offset, reply.data, r_payload * sizeof(int32_t));
            received[r_seq] = true;
            retries = 0;
        }
    }

    for (size_t i = 0; i < count; ++i) {
        recvbuf[i] = (float)accum_ints[i] / SCALE;
    }
    return 0;
}

extern "C" int switchml_finalize() {
    if (sockfd >= 0) close(sockfd);
    sockfd = -1;
    initialized = false;
    return 0;
}