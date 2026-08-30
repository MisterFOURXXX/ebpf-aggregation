# Clean up the repo cloned in the Windows drive
cd /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation
rm -rf bpftool

# Clone and build inside native Linux storage (/tmp)
cd /tmp
git clone --recurse-submodules https://github.com/libbpf/bpftool.git
cd bpftool/src
make -j$(nproc)
sudo make install

# Verify the binary works and is in PATH
bpftool version

# Install missing OpenSSL development headers
sudo apt-get update && sudo apt-get install -y libssl-dev

# Resume the build and installation
cd /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/bpftool/src
make -j$(nproc)
sudo make install

sudo apt-get install -y binutils-dev
cd /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/bpftool/src
make clean
make -j$(nproc)
sudo make install

sudo apt update && sudo apt install -y build-essential git libelf-dev libssl-dev zlib1g-dev xxd clang llvm
git clone --recurse-submodules https://github.com/libbpf/bpftool.git
cd bpftool/src
make -j$(nproc)
sudo make install
bpftool version

cd /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build
sudo rm -rf *
sudo cmake .. -DCMAKE_BUILD_TYPE=Release
sudo make -j$(nproc)make clean

ls -l build/benchmarks/latency_benchmark

sudo apt-get update
sudo apt-get install -y x11-xserver-utils xterm

# Latency
rm -rf build
sudo mn -c
sudo python3 scripts/run_mininet_topo.py
mininet> agg pkill -9 -f simple_allreduce
mininet> agg pkill -9 -f controller.py
mininet> agg pkill -9 -f latency_benchmark
mininet> agg pkill -9 -f controller.py
mininet> agg python3 controller/controller.py &
mininet> w0 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 0 32 100 &
mininet> w1 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 1 32 100 &
mininet> w2 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 2 32 100 &
mininet> w3 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 3 32 100 & 
mininet> agg ip a
If workers hang or time out, ensure the controller is still running and the eBPF program is attached (sudo ip link show agg-eth0 | grep xdp).

# CPU
w0 /mnt/c/Users/ADMIN/Documents/Github/ebpf-aggregation/build/benchmarks/cpu_benchmark 192.168.1.100 9999 0 32 100

# Scalability Benchmark – run from the host (not inside Mininet)
./build/benchmarks/scalability_benchmark 192.168.1.100 9999 4 32 100


w0 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/examples/simple_allreduce 192.168.1.100 9999 0 &
w1 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/examples/simple_allreduce 192.168.1.100 9999 1 &
w2 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/examples/simple_allreduce 192.168.1.100 9999 2 &
w3 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/examples/simple_allreduce 192.168.1.100 9999 3 &

sudo apt update
sudo apt install -y ntpdate
sudo ntpdate time.windows.com
find . -type f -exec touch {} \;find . -type f -exec touch {} \;

# 1. Copy your repository into your native Linux home directory
mkdir -p ~/projects
cp -r /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation ~/projects/
cd ~/projects/ebpf-aggregation

# 2. Clean out corrupted CMake cache artifacts
rm -rf build/ CMakeFiles/ CMakeCache.txt

# 3. Rebuild natively inside Linux
mkdir build && cd build
cmake ..
make -j$(nproc)

sudo mn -c
python3 scripts/run_mininet_topo.py
mininet> agg pkill -9 -f latency_benchmark
mininet> agg pkill -9 -f controller.py
mininet> agg python3 -u controller/controller.py > controller.log 2>&1 &
mininet> w0 stdbuf -oL /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 0 32 100 > w0.log 2>&1 &
mininet> w1 stdbuf -oL /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 1 32 100 > w1.log 2>&1 &
mininet> w2 stdbuf -oL /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 2 32 100 > w2.log 2>&1 &
mininet> w3 stdbuf -oL /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 3 32 100 > w3.log 2>&1 &

mininet> agg pkill -9 -f latency_benchmark
mininet> agg pkill -9 -f controller.py
mininet> agg python3 -u controller/controller.py &
mininet> w0 stdbuf -oL /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 0 32 100 &
mininet> w1 stdbuf -oL /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 1 32 100 &
mininet> w2 stdbuf -oL /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 2 32 100 &
mininet> w3 stdbuf -oL /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 3 32 100 &