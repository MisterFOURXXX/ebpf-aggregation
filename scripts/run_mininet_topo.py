#!/usr/bin/env python3
import os
import sys
import subprocess
from mininet.net import Mininet
from mininet.cli import CLI
from mininet.log import setLogLevel, info

def cleanup_interfaces():
    """Remove any leftover veth interfaces from previous runs."""
    os.system("ip link show | grep -E 'agg-eth0|s1-eth' | awk -F: '{print $2}' | xargs -r ip link del 2>/dev/null")

def compile_ebpf(project_root):
    ebpf_dir = os.path.join(project_root, "ebpf")
    obj_file = os.path.join(ebpf_dir, "aggregator.bpf.o")
    if os.path.exists(obj_file):
        info("*** eBPF object already compiled.\n")
        return obj_file
    info("*** eBPF object not found. Compiling now...\n")
    try:
        subprocess.run(["make", "-C", ebpf_dir], capture_output=True, text=True, check=True)
        info("*** Compilation successful.\n")
        return obj_file
    except Exception as e:
        info(f"*** ERROR: Could not compile eBPF: {e}\n")
        sys.exit(1)

def create_topology():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    ebpf_obj = compile_ebpf(project_root)

    # --- CLEANUP: remove stale interfaces ---
    cleanup_interfaces()
    info("*** Stale interfaces cleaned up.\n")

    net = Mininet()

    agg = net.addHost('agg', ip='192.168.1.100/24')
    workers = []
    for i in range(4):
        w = net.addHost(f'w{i}', ip=f'192.168.1.{101+i}/24')
        workers.append(w)

    switch = net.addSwitch('s1')

    net.addLink(agg, switch)
    for w in workers:
        net.addLink(w, switch)

    net.start()
    info("*** Mininet network started.\n")

    # --- FIX: add a normal flow to the switch ---
    agg.cmd("ovs-ofctl add-flow s1 actions=normal")
    agg.cmd("ovs-vsctl set bridge s1 fail_mode=standalone")
    info("*** OVS switch configured to flood.\n")

    # Mount BPF filesystem
    agg.cmd("mount -t bpf bpf /sys/fs/bpf 2>/dev/null")
    agg.cmd("mkdir -p /sys/fs/bpf/tc 2>/dev/null")

    info(f"*** Attaching XDP object: {ebpf_obj}\n")
    attach_cmd = f"ip link set dev agg-eth0 xdp obj {ebpf_obj} sec xdp"
    result = agg.cmd(attach_cmd + " 2>&1")
    if "Error" in result or "Failed" in result:
        info(f"*** ERROR: {result}\n")
        net.stop()
        sys.exit(1)
    info("*** XDP attached successfully.\n")

    info("\n" + "=" * 40 + "\n")
    info("=== Mininet Topology Ready ===\n")
    info("Aggregator: 192.168.1.100 (agg-eth0)\n")
    info("Workers:    192.168.1.101 - 192.168.1.104\n")
    info("XDP is attached to agg-eth0.\n")
    info("=" * 40 + "\n")

    CLI(net)

    agg.cmd("ip link set dev agg-eth0 xdp off 2>/dev/null")
    net.stop()
    info("*** Mininet stopped.\n")

if __name__ == "__main__":
    setLogLevel('info')
    create_topology()