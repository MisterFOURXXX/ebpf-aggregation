# ebpf_loader.py
import subprocess
import os
import json
import time

def attach_xdp(interface: str, obj_path: str = "ebpf/aggregator.bpf.o"):
    """Attach XDP program using bpftool."""
    cmd = f"bpftool net attach xdp obj {obj_path} sec xdp dev {interface}"
    subprocess.run(cmd, shell=True, check=True)
    print(f"[OK] XDP attached to {interface}")

def detach_xdp(interface: str):
    subprocess.run(f"bpftool net detach xdp dev {interface}", shell=True, stderr=subprocess.DEVNULL)
    print(f"[OK] XDP detached from {interface}")

def update_config_map(session_id: int, expected_workers: int):
    """Write expected worker count to config_map."""
    key_hex = f"0x{session_id:08x}"
    val_hex = f"0x{expected_workers:02x} 0x00 0x00 0x00"
    cmd = f'bpftool map update name config_map key {key_hex} value {val_hex}'
    subprocess.run(cmd, shell=True, check=True)
    print(f"[OK] Config map updated: session {session_id} -> {expected_workers} workers")

def pin_map(map_name: str, pin_path: str):
    """Pin BPF map to /sys/fs/bpf for user-space access."""
    subprocess.run(f"bpftool map pin name {map_name} {pin_path}", shell=True)