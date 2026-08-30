#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: sudo $0 <interface>"
    exit 1
fi
INTERFACE=$1
sudo ip link set dev $INTERFACE xdp obj ebpf/aggregator.bpf.o sec xdp
echo "XDP attached to $INTERFACE"
sudo bpftool net list | grep -A 2 xdp