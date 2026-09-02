#!/bin/bash
# Attach XDP to given interface (default lo)
INTERFACE=${1:-lo}
echo "Attaching XDP program aggregator.bpf.o to $INTERFACE"
sudo bpftool net attach xdp obj ../ebpf/aggregator.bpf.o sec xdp dev $INTERFACE
sudo bpftool net list