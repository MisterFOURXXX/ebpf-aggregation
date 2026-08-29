#!/usr/bin/env python3
# run_mininet_topo.py - Creates a virtual network for testing eBPF without hardware
from mininet.net import Mininet
from mininet.node import Host
from mininet.cli import CLI
from mininet.log import setLogLevel
import os

def create_topology():
    net = Mininet()
    
    # Aggregator node
    agg = net.addHost('agg', ip='192.168.1.100/24')
    
    # Workers
    workers = []
    for i in range(4):
        w = net.addHost(f'w{i}', ip=f'192.168.1.{101+i}/24')
        workers.append(w)
    
    # Switch
    switch = net.addSwitch('s1')
    
    # Links
    net.addLink(agg, switch)
    for w in workers:
        net.addLink(w, switch)
    
    net.start()
    
    # Enable XDP on the aggregator's interface (veth pair)
    # In mininet, the interface for agg is 'agg-eth0'
    os.system("sudo bpftool net attach xdp obj ebpf/aggregator.bpf.o sec xdp dev agg-eth0")
    
    print("=== Mininet Topology Ready ===")
    print("Aggregator: 192.168.1.100 (agg-eth0)")
    print("Workers: 192.168.1.101-104")
    print("XDP attached to agg-eth0")
    print("Run workers with: ./build/examples/simple_allreduce 192.168.1.100 9999 <worker_id>")
    
    CLI(net)
    net.stop()
    os.system("sudo bpftool net detach xdp dev agg-eth0")

if __name__ == "__main__":
    setLogLevel('info')
    create_topology()