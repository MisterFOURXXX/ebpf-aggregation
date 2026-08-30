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

Latency
rm -rf build
sudo mn -c
sudo python3 scripts/run_mininet_topo.py
mininet> agg python3 controller/controller.py &
mininet> w0 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.101 9999 0 32 100 &
mininet> w1 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.102 9999 1 32 100 &
mininet> w2 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.103 9999 2 32 100 &
mininet> w3 /mnt/c/Users/ADMIN/Documents/GitHub/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.104 9999 3 32 100 
mininet> agg ip a
If workers hang or time out, ensure the controller is still running and the eBPF program is attached (sudo ip link show agg-eth0 | grep xdp).

CPU
w0 /mnt/c/Users/ADMIN/Documents/Github/ebpf-aggregation/build/benchmarks/cpu_benchmark 192.168.1.100 9999 0 32 100

Scalability Benchmark – run from the host (not inside Mininet)
./build/benchmarks/scalability_benchmark 192.168.1.100 9999 4 32 100

w2 /mnt/c/Users/ADMIN/Documents/Github/ebpf-aggregation/build/benchmarks/latency_benchmark 192.168.1.100 9999 2 32 100


sudo apt update
sudo apt install -y ntpdate
sudo ntpdate time.windows.com
find . -type f -exec touch {} \;find . -type f -exec touch {} \;