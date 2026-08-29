// switchml.h
#pragma once
#include <cstddef>
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize: connect to aggregator, set worker ID, and assign a unique session ID.
// Multiple independent training jobs can share the same aggregator using different session IDs.
int switchml_init(const char* aggregator_ip, int port, int worker_id, uint32_t session_id);

// Perform AllReduce: sums 'count' floats from sendbuf, stores result in recvbuf.
// Uses the session_id provided during initialization.
int switchml_allreduce(const float* sendbuf, float* recvbuf, size_t count);

// Cleanup resources (close socket, etc.)
int switchml_finalize();

#ifdef __cplusplus
}
#endif