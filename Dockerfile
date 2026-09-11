FROM ubuntu:22.04

# Install dependencies - suppress ALL output
RUN apt-get update -qq 2>&1 >/dev/null && \
    apt-get install -y -qq \
    make gcc clang llvm libbpf-dev \
    linux-tools-common linux-headers-generic \
    linux-libc-dev \
    cmake python3 python3-pip 2>&1 >/dev/null && \
    rm -rf /var/lib/apt/lists/* 2>&1 >/dev/null

# Create symlink for asm/types.h
RUN ln -sf /usr/include/$(uname -m)-linux-gnu/asm /usr/include/asm 2>/dev/null || true

WORKDIR /app
COPY . .

RUN chmod +x scripts/*.sh

# Build - suppress all output, only show final status
RUN echo "Building..." && \
    ./scripts/clean_all.sh 2>&1 >/dev/null && \
    make all 2>&1 >/dev/null && \
    echo "Build: OK" || echo "Build: FAILED"

# Tests - suppress all output, only show final status
RUN echo "Testing..." && \
    cd tests && mkdir -p build && cd build && \
    cmake .. 2>&1 >/dev/null && \
    make 2>&1 >/dev/null && \
    ctest 2>&1 >/dev/null && \
    echo "Tests: OK" || echo "Tests: FAILED"

CMD ["/bin/bash"]
