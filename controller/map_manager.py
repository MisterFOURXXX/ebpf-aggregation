# map_manager.py - Read/write BPF maps from userspace
import subprocess
import json
import os

def get_map_id(map_name: str) -> int:
    """Get BPF map ID by name using bpftool."""
    result = subprocess.check_output(
        f"bpftool map show name {map_name} -jp", 
        shell=True, stderr=subprocess.DEVNULL
    )
    data = json.loads(result)
    if data and len(data) > 0:
        return data[0]["id"]
    raise RuntimeError(f"Map {map_name} not found")

def read_map(map_name: str, key_hex: str) -> bytes:
    """Read a value from a BPF map."""
    map_id = get_map_id(map_name)
    cmd = f"bpftool map lookup id {map_id} key {key_hex}"
    result = subprocess.check_output(cmd, shell=True)
    # Parse hex output (simplified)
    return result

def write_map(map_name: str, key_hex: str, value_hex: str):
    """Write a value to a BPF map."""
    map_id = get_map_id(map_name)
    cmd = f"bpftool map update id {map_id} key {key_hex} value {value_hex}"
    subprocess.run(cmd, shell=True, check=True)

def pin_map(map_name: str, pin_path: str):
    """Pin map for persistence."""
    try:
        subprocess.run(f"bpftool map pin name {map_name} {pin_path}", shell=True, check=True)
    except subprocess.CalledProcessError:
        # Maybe already pinned
        pass