#!/bin/bash
echo "[clean-docker] Removing Docker and KIND leftovers"

sudo docker stop -t 0 ebpf-test-control-plane 2>/dev/null || true
sudo docker rm -f ebpf-test-control-plane 2>/dev/null || true
sudo docker network rm kind 2>/dev/null || true
sudo kind delete cluster --name ebpf-test 2>/dev/null || true
sudo docker rmi -f ebpf-p4-agg:latest 2>/dev/null || true

echo "[clean-docker] Done"
