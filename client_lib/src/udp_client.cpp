#include "switchml.h"
#include <iostream>
#include <vector>
#include <cstring>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/poll.h>
#include <errno.h>

static int g_sockfd = -1;
static struct sockaddr_in g_server_addr;
static int g_worker_id = -1;
static uint32_t g_seq_num = 0;
static const uint32_t g_session_id = 0x12345678;
static const int MAX_RETRIES = 200;          // Increased for reliable tests
static const size_t MAX_PAYLOAD_INTS = 32;

extern "C" int switchml_init(const char* ip, int port, int worker_id) {
    g_worker_id = worker_id;
    g_seq_num = 0;

    g_sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (g_sockfd < 0) return -1;

    struct timeval tv;
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    setsockopt(g_sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    memset(&g_server_addr, 0, sizeof(g_server_addr));
    g_server_addr.sin_family = AF_INET;
    g_server_addr.sin_port = htons(port);
    inet_pton(AF_INET, ip, &g_server_addr.sin_addr);

    struct sockaddr_in local;
    memset(&local, 0, sizeof(local));
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = INADDR_ANY;
    local.sin_port = 0;
    bind(g_sockfd, reinterpret_cast<struct sockaddr*>(&local), sizeof(local));

    std::cout << "[CLIENT] Worker " << worker_id << " initialized, target " << ip << ":" << port << "\n";
    return 0;
}

extern "C" void switchml_reset_seq(uint32_t new_seq) {
    g_seq_num = new_seq;
}

extern "C" int switchml_allreduce(const int32_t* sendbuf, int32_t* recvbuf, size_t count) {
    if (g_sockfd < 0 || count > MAX_PAYLOAD_INTS) return -1;

    uint8_t packet_buffer[256];
    memset(packet_buffer, 0, sizeof(packet_buffer));

    auto* hdr = reinterpret_cast<struct gradient_hdr*>(packet_buffer);
    hdr->session_id = g_session_id;
    hdr->seq_num = g_seq_num;
    hdr->worker_id = static_cast<uint16_t>(g_worker_id);
    hdr->payload_ints = static_cast<uint16_t>(count);

    int32_t* payload_ptr = reinterpret_cast<int32_t*>(hdr + 1);
    memcpy(payload_ptr, sendbuf, count * sizeof(int32_t));

    size_t packet_size = sizeof(struct gradient_hdr) + (count * sizeof(int32_t));

    int attempts = 0;
    bool success = false;

    while (attempts < MAX_RETRIES) {
        ssize_t sent = sendto(g_sockfd, packet_buffer, packet_size, 0,
                              reinterpret_cast<struct sockaddr*>(&g_server_addr),
                              sizeof(g_server_addr));
        if (sent < 0) {
            std::cerr << "[CLIENT] sendto error (" << attempts << "): " << strerror(errno) << "\n";
            attempts++;
            usleep(5000);
            continue;
        }

        uint8_t response_buffer[256];
        struct sockaddr_in from_addr;
        socklen_t from_len = sizeof(from_addr);

        ssize_t received = recvfrom(g_sockfd, response_buffer, sizeof(response_buffer), 0,
                                    reinterpret_cast<struct sockaddr*>(&from_addr), &from_len);
        if (received < 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                std::cerr << "[CLIENT] recvfrom error (" << attempts << "): " << strerror(errno) << "\n";
            }
            attempts++;
            continue;
        }

        if (received >= static_cast<ssize_t>(sizeof(struct gradient_hdr))) {
            auto* resp_hdr = reinterpret_cast<struct gradient_hdr*>(response_buffer);
            if (resp_hdr->session_id == g_session_id && resp_hdr->seq_num == g_seq_num) {
                int32_t* resp_payload = reinterpret_cast<int32_t*>(resp_hdr + 1);
                memcpy(recvbuf, resp_payload, count * sizeof(int32_t));
                success = true;
                break;
            }
        }
        attempts++;
    }

    if (!success) {
        std::cerr << "[CLIENT] AllReduce failed after " << MAX_RETRIES << " attempts (seq " << g_seq_num << ")\n";
        return -1;
    }

    g_seq_num++;
    return 0;
}

extern "C" int switchml_finalize() {
    if (g_sockfd >= 0) {
        close(g_sockfd);
        g_sockfd = -1;
    }
    return 0;
}