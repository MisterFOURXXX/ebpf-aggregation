#!/bin/bash
INTERFACE=${1:-lo}
echo "Attaching XDP program to $INTERFACE"
sudo bpftool net attach xdp name xdp_aggregator dev $INTERFACE
sudo bpftool net list
