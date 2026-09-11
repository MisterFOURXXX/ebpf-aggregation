#!/bin/bash
INTERFACE=${1:-lo}
echo "Attaching XDP program to $INTERFACE"
# Use the correct syntax: attach xdp (dev) (program name)
sudo bpftool net attach xdp name xdp_aggregator dev $INTERFACE
sudo bpftool net list
