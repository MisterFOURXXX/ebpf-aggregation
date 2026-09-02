#!/bin/bash
set -e
INTERFACE=${1:-eth0}
echo "Detaching XDP from $INTERFACE (to use kernel stack for replies)"
sudo bpftool net detach xdp dev $INTERFACE
echo "Simulated: XDP_TX disabled."