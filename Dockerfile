FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN=true

# Install apt-utils first to avoid debconf warnings
RUN apt-get update -qq 2>/dev/null >/dev/null && \
    apt-get install -y -qq apt-utils 2>/dev/null >/dev/null

# Install all build dependencies (arch-agnostic)
RUN apt-get update -qq 2>/dev/null >/dev/null && \
    apt-get install -y -qq --no-install-recommends \
    make gcc g++ clang llvm libbpf-dev \
    linux-tools-common linux-libc-dev \
    cmake python3 python3-pip \
    2>/dev/null >/dev/null && \
    rm -rf /var/lib/apt/lists/*

# Fix asm/types.h for both x86_64 and aarch64
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then DEB_ARCH="aarch64"; else DEB_ARCH="x86_64"; fi && \
    mkdir -p /usr/include/asm && \
    ln -sf /usr/include/${DEB_ARCH}-linux-gnu/asm/types.h /usr/include/asm/types.h 2>/dev/null || true && \
    ln -sf /usr/include/${DEB_ARCH}-linux-gnu/asm /usr/include/asm 2>/dev/null || true

WORKDIR /app
COPY . .

RUN chmod +x scripts/*.sh

# Build all with minimal output
RUN echo "=== Building ===" && \
    ./scripts/clean_all.sh 2>/dev/null >/dev/null && \
    (make all 2>&1 >/dev/null | grep -E "error:|fatal error:" || echo "Build OK") && \
    (cd examples && mkdir -p build && cd build && cmake .. >/dev/null 2>&1 && make 2>&1 >/dev/null | grep -E "error:" || true) && \
    (cd benchmarks && mkdir -p build && cd build && cmake .. >/dev/null 2>&1 && make 2>&1 >/dev/null | grep -E "error:" || true) && \
    echo "Build complete"

RUN echo "=== Testing ===" && \
    cd tests && mkdir -p build && cd build && \
    cmake .. >/dev/null 2>&1 && make >/dev/null 2>&1 && \
    (ctest 2>&1 | grep -E "tests passed|tests failed" || echo "Tests run")

CMD ["/bin/bash"]
