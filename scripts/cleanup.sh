#!/bin/bash
kubectl delete -f operator/config/sample/gradientaggregation.yaml
sudo bpftool net detach xdp dev lo 2>/dev/null
sudo rm -rf /sys/fs/bpf/ebpf_agg