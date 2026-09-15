#!/bin/bash
# ============================================================
# setup.sh - environment setup (Oracle Cloud ARM64/x86_64)
# ============================================================
set +e

echo "Setup: installing build and test dependencies"

sudo apt-get update -qq
sudo apt-get install -y -qq \
    make gcc g++ clang llvm libbpf-dev \
    linux-tools-common linux-libc-dev \
    linux-headers-$(uname -r) \
    cmake python3 python3-pip \
    python3-matplotlib python3-numpy \
    dos2unix file curl wget gnupg ca-certificates \
    psmisc lsof iproute2 bsdextrautils \
    docker.io

# bpftool via kernel-matched tools
if ! command -v bpftool >/dev/null 2>&1; then
    KVER=$(uname -r)
    sudo apt-get install -y -qq linux-tools-${KVER} 2>/dev/null || \
    sudo apt-get install -y -qq linux-tools-generic 2>/dev/null || true
fi

# kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    if command -v snap >/dev/null 2>&1; then
        sudo snap install kubectl --classic
    fi
fi

# KIND
if ! command -v kind >/dev/null 2>&1; then
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  KIND_ARCH=amd64 ;;
        aarch64) KIND_ARCH=arm64 ;;
        *)       KIND_ARCH=amd64 ;;
    esac
    curl -Lo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-${KIND_ARCH}"
    chmod +x /tmp/kind
    sudo mv /tmp/kind /usr/local/bin/kind
fi

# Go
if ! command -v go >/dev/null 2>&1; then
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  GO_ARCH=amd64 ;;
        aarch64) GO_ARCH=arm64 ;;
        *)       GO_ARCH=amd64 ;;
    esac
    curl -Lo /tmp/go.tgz "https://go.dev/dl/go1.21.0.linux-${GO_ARCH}.tar.gz"
    sudo tar -C /usr/local -xzf /tmp/go.tgz
    rm -f /tmp/go.tgz
    echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh >/dev/null
    export PATH=$PATH:/usr/local/go/bin
fi

sudo usermod -aG docker "$USER" 2>/dev/null || true

echo "Setup complete."
echo "Kernel:  $(uname -r)  (must be >= 5.15)"
echo "kubectl: $(command -v kubectl || echo missing)"
echo "kind:    $(command -v kind    || echo missing)"
echo "go:      $(command -v go      || echo missing)"
echo "bpftool: $(command -v bpftool || echo missing)"
echo "column:  $(command -v column  || echo missing)"
echo "fuser:   $(command -v fuser   || echo missing)"
echo "lsof:    $(command -v lsof    || echo missing)"
echo "Log out and back in if docker group was just added."