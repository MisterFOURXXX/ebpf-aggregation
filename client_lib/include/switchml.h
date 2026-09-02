#pragma once
#include <cstddef>
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

int switchml_init(const char* aggregator_ip, int port, int worker_id, uint32_t session_id);
int switchml_allreduce(const float* sendbuf, float* recvbuf, size_t count);
int switchml_finalize();

#ifdef __cplusplus
}
#endif