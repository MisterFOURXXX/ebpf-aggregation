#!/bin/bash
# setup_env.sh - Installs all dependencies for eBPF-Agg

set -e

echo "[1/5] Updating packages..."
sudo apt update -y

echo "[2/5] Installing eBPF toolchain..."
sudo apt install -y clang llvm libelf-dev linux-tools-common \
    linux-tools-$(uname -r) libbpf-dev build-essential cmake \
    linux-headers-$(uname -r)

echo "[3/5] Installing Python dependencies..."
pip3 install -r requirements.txt

echo "[4/5] Compiling eBPF program..."
cd ebpf && make && cd ..

echo "[5/5] Compiling C++ components..."
mkdir -p build && cd build && cmake .. && make -j$(nproc) && cd ..

echo "[OK] Setup complete!"
echo "Next steps:"
echo "1. Attach XDP: sudo scripts/attach_xdp.sh eth0"
echo "2. Run controller: python controller/controller.py"
echo "3. Run examples: ./build/examples/simple_allreduce <ip> <port> <worker_id>"