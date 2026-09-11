#include "../include/switchml.h"
#include "../include/chunker.h"
#include <cstring>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <poll.h>
#include <vector>
#include <chrono>
#include <iostream>

// Thread-local state: each thread has its own socket
thread_local int           t_sockfd      = -1;
thread_local sockaddr_in   t_agg_addr{};
thread_local uint32_t      t_session_id  = 0;
thread_local uint16_t      t_worker_id   = 0;
thread_local bool          t_initialized = false;

struct Packet {
    uint8_t header[12];
    int32_t data[128];
};

static inline size_t count_received(const std::vector<bool>& r) {
    size_t n = 0;
    for (bool b : r) if (b) n++;
    return n;
}

extern "C" int switchml_init(const char* ip, int port, int wid, uint32_t sid) {
    if (t_initialized) switchml_finalize();
    t_sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (t_sockfd < 0) return -1;

    int buf = 32 * 1024 * 1024;
    setsockopt(t_sockfd, SOL_SOCKET, SO_RCVBUF, &buf, sizeof(buf));
    setsockopt(t_sockfd, SOL_SOCKET, SO_SNDBUF, &buf, sizeof(buf));

    memset(&t_agg_addr, 0, sizeof(t_agg_addr));
    t_agg_addr.sin_family = AF_INET;
    t_agg_addr.sin_port   = htons(port);
    if (inet_pton(AF_INET, ip, &t_agg_addr.sin_addr) <= 0) {
        close(t_sockfd); t_sockfd = -1; return -1;
    }
    t_worker_id = (uint16_t)wid;
    t_session_id = sid;
    t_initialized = true;
    return 0;
}

extern "C" int switchml_allreduce(const float* sendbuf, float* recvbuf, size_t count) {
    if (!t_initialized || t_sockfd < 0) return -1;
    const int SCALE = 1000;
    std::vector<int32_t> send_int(count);
    for (size_t i = 0; i < count; ++i)
        send_int[i] = (int32_t)(sendbuf[i] * SCALE + 0.5f);

    std::vector<Chunk> chunks = split_tensor(count);
    size_t num_packets = chunks.size();
    std::vector<Packet> packets(num_packets);

    for (size_t i = 0; i < num_packets; ++i) {
        pack_chunk(send_int.data(), chunks[i].offset, chunks[i].num_ints,
                   packets[i].header, t_session_id, (uint32_t)i, t_worker_id);
        memcpy(packets[i].data, send_int.data() + chunks[i].offset,
               chunks[i].num_ints * sizeof(int32_t));
    }

    for (size_t i = 0; i < num_packets; ++i) {
        size_t len = 12 + chunks[i].num_ints * sizeof(int32_t);
        if (sendto(t_sockfd, &packets[i], len, 0,
                   (struct sockaddr*)&t_agg_addr, sizeof(t_agg_addr)) < 0)
            return -1;
    }

    std::vector<int32_t> accum(count, 0);
    std::vector<bool> received(num_packets, false);
    struct pollfd pfd = { .fd = t_sockfd, .events = POLLIN };
    int retries = 0;
    int max_retries = 500 + (int)(num_packets * 3);
    if (max_retries < 2000) max_retries = 2000;

    while (true) {
        bool done = true;
        for (bool r : received) if (!r) { done = false; break; }
        if (done) break;

        int ret = poll(&pfd, 1, 1);
        if (ret < 0) return -1;
        if (ret == 0) {
            if (++retries > max_retries) return -1;
            continue;
        }

        Packet reply;
        struct sockaddr_in src;
        socklen_t slen = sizeof(src);
        int n = recvfrom(t_sockfd, &reply, sizeof(Packet), MSG_DONTWAIT,
                         (struct sockaddr*)&src, &slen);
        if (n < 12) continue;

        uint32_t rs, rq;
        uint16_t rw, rp;
        memcpy(&rs, reply.header,     4);
        memcpy(&rq, reply.header + 4, 4);
        memcpy(&rw, reply.header + 8, 2);
        memcpy(&rp, reply.header + 10,2);

        if (rs != t_session_id || rq >= num_packets) continue;
        if (!received[rq]) {
            size_t off = chunks[rq].offset;
            if (off + rp <= count) {
                memcpy(accum.data() + off, reply.data, rp * sizeof(int32_t));
                received[rq] = true;
                retries = 0;
            }
        }
    }

    for (size_t i = 0; i < count; ++i)
        recvbuf[i] = (float)accum[i] / SCALE;
    return 0;
}

extern "C" int switchml_finalize() {
    if (t_sockfd >= 0) close(t_sockfd);
    t_sockfd = -1;
    t_initialized = false;
    return 0;
}
