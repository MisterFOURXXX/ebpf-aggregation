# Benchmarking Methodology

We measure:
- **Latency** vs. payload size (64 bytes to 1 MB)
- **CPU utilization** of the aggregator node
- **Scalability** with increasing number of workers (2‑16)

Baselines: standard UDP, NCCL (if available).

Expected results: eBPF‑based All‑Reduce latency < 200 µs for small payloads, CPU < 5%.