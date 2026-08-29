// udp_client.cpp
#include "switchml.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cstring>
#include <vector>
#include <iostream>
#include <chrono>

static int sockfd = -1;
static struct sockaddr_in agg_addr;
static int worker_id = 0;
static uint32_t session_id = 0x12345678;  // Hardcoded for MVP
static const size_t MAX_FLOATS_PER_PKT = 32; // 128 bytes

// Packet structure (must match eBPF aggregator.h)
struct __attribute__((packed)) Packet {
    uint32_t session_id;
    uint32_t seq_num;
    uint16_t worker_id;
    uint16_t payload_floats;
    float data[MAX_FLOATS_PER_PKT];
};

extern "C" int switchml_init(const char* ip, int port, int wid) {
    worker_id = wid;
    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) return -1;

    // Set timeout to avoid hanging
    struct timeval tv = { .tv_sec = 5, .tv_usec = 0 };
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    memset(&agg_addr, 0, sizeof(agg_addr));
    agg_addr.sin_family = AF_INET;
    agg_addr.sin_port = htons(port);
    inet_pton(AF_INET, ip, &agg_addr.sin_addr);

    // Bind to a random port to receive replies
    struct sockaddr_in local;
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = INADDR_ANY;
    local.sin_port = 0;
    bind(sockfd, (struct sockaddr*)&local, sizeof(local));

    return 0;
}

extern "C" int switchml_allreduce(const float* sendbuf, float* recvbuf, size_t count) {
    if (sockfd < 0) return -1;

    size_t num_packets = (count + MAX_FLOATS_PER_PKT - 1) / MAX_FLOATS_PER_PKT;
    std::vector<struct mmsghdr> msgs(num_packets);
    std::vector<struct iovec> iovs(num_packets);
    std::vector<Packet> packets(num_packets);

    // 1. Send all chunks using sendmmsg (reduces syscall overhead)
    for (size_t i = 0; i < num_packets; i++) {
        Packet &pkt = packets[i];
        pkt.session_id = session_id;
        pkt.seq_num = i;
        pkt.worker_id = worker_id;
        size_t offset = i * MAX_FLOATS_PER_PKT;
        size_t remaining = count - offset;
        pkt.payload_floats = (remaining < MAX_FLOATS_PER_PKT) ? remaining : MAX_FLOATS_PER_PKT;
        memcpy(pkt.data, sendbuf + offset, pkt.payload_floats * sizeof(float));

        iovs[i].iov_base = &pkt;
        iovs[i].iov_len = sizeof(Packet);
        msgs[i].msg_hdr.msg_name = &agg_addr;
        msgs[i].msg_hdr.msg_namelen = sizeof(agg_addr);
        msgs[i].msg_hdr.msg_iov = &iovs[i];
        msgs[i].msg_hdr.msg_iovlen = 1;
    }

    int sent = sendmmsg(sockfd, msgs.data(), num_packets, 0);
    if (sent < 0) return -1;

    // 2. Receive the aggregated result from the eBPF aggregator (XDP_TX)
    // The reply comes from the aggregator IP, same port.
    struct pollfd pfd = { .fd = sockfd, .events = POLLIN };
    size_t received_packets = 0;
    int retries = 0;

    while (received_packets < num_packets && retries < 50) {
        int ret = poll(&pfd, 1, 1); // 1ms timeout (much shorter than usleep(1000))
        if (ret <= 0) {
            retries++;
            continue;
        }
        Packet reply_pkt;
        struct sockaddr_in src;
        socklen_t src_len = sizeof(src);
        int n = recvfrom(sockfd, &reply_pkt, sizeof(Packet), MSG_DONTWAIT,
                        (struct sockaddr*)&src, &src_len);
        if (n < 0) continue;
        if (n < 0) {
            retries++;
            usleep(1000);  // 1ms backoff
            continue;
        }
        if (reply_pkt.session_id != session_id) continue; // Ignore other sessions
        // Assemble recvbuf based on seq_num
        size_t offset = reply_pkt.seq_num * MAX_FLOATS_PER_PKT;
        if (offset + reply_pkt.payload_floats <= count) {
            memcpy(recvbuf + offset, reply_pkt.data,
                   reply_pkt.payload_floats * sizeof(float));
            received_packets++;
        }
    }

    return (received_packets == num_packets) ? 0 : -1;
}

extern "C" int switchml_finalize() {
    if (sockfd >= 0) close(sockfd);
    return 0;
}