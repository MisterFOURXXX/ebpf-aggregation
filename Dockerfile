FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Base packages: build toolchain + runtime tools the harness needs.
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        make gcc g++ clang llvm libbpf-dev \
        linux-tools-common linux-libc-dev \
        cmake python3 python3-pip \
        python3-matplotlib python3-numpy \
        sudo psmisc lsof iproute2 procps \
        iputils-ping net-tools bash coreutils \
        dos2unix file \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

# Build the eBPF object.
RUN make -C ebpf

# Build the C++ components.
RUN (cd client_lib && mkdir -p build && cd build && cmake .. >/dev/null && make >/dev/null) && \
    (cd examples   && mkdir -p build && cd build && cmake .. >/dev/null && make >/dev/null) && \
    (cd benchmarks && mkdir -p build && cd build && cmake .. >/dev/null && make >/dev/null) && \
    (cd tests      && mkdir -p build && cd build && cmake .. >/dev/null && make >/dev/null)

RUN chmod +x scripts/*.sh benchmarks/ablation/*.sh benchmarks/analysis/*.py 2>/dev/null || true

# Sanity check: all runtime tools must be present.
RUN for t in ss fuser lsof pgrep setsid sudo python3; do \
        command -v "$t" >/dev/null || { echo "MISSING: $t"; exit 1; }; \
    done

# Run the unit tests as a final build assertion.
RUN cd tests/build && ctest --output-on-failure

CMD ["/bin/bash"]