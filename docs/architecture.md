# Architecture

The system uses eBPF/XDP for host‑level aggregation and P4 for switch‑level offload. The Kubernetes Operator manages the lifecycle via Custom Resources. bpfd provides a unified interface to load/unload eBPF programs across the cluster.

Data flow:
1. Worker computes gradients.
2. Client library chunks tensor into UDP packets.
3. XDP program on aggregator node intercepts and aggregates in per‑CPU BPF maps.
4. When all workers' contributions arrive, aggregated result is sent back.
5. Metrics exported via BPF maps to Prometheus.