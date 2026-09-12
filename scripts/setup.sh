#!/bin/bash
# ============================================================
# setup.sh - Environment setup for Oracle Cloud VM
# ============================================================
sudo apt update
sudo apt install -y make gcc clang llvm libbpf-dev linux-tools-common \
    linux-tools-$(uname -r) bpftool docker.io kubectl \
    linux-headers-$(uname -r) linux-libc-dev \
    cmake python3 python3-pip

# Install Go
if ! command -v go > /dev/null 2>&1; then
    wget -q https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
    rm -f go1.21.0.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
fi

# Install KIND (auto-detect architecture)
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  KIND_ARCH="amd64" ;;
    aarch64) KIND_ARCH="arm64" ;;
    *)       KIND_ARCH="amd64" ;;
esac
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-${KIND_ARCH}
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Add current user to docker group
sudo usermod -aG docker $USER

echo "Dependencies installed. Kernel version must be >=5.15."
echo "Please log out and back in for docker group to take effect."
