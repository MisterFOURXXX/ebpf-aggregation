import subprocess
import json
import os

def get_map_id(map_name: str) -> int:
    """Get BPF map ID by name using bpftool."""
    try:
        result = subprocess.check_output(
            f"bpftool map show name {map_name} -jp",
            shell=True, stderr=subprocess.DEVNULL
        )
        data = json.loads(result)
        if isinstance(data, list) and len(data) > 0:
            return data[0]["id"]
        elif isinstance(data, dict):
            return data["id"]
        raise RuntimeError(f"Map {map_name} not found")
    except subprocess.CalledProcessError:
        raise RuntimeError(f"Failed to query map {map_name}")

def read_map(map_name: str, key_hex: str) -> bytes:
    """Read a value from a BPF map. key_hex is a space‑separated hex string."""
    map_id = get_map_id(map_name)
    cmd = f"bpftool map lookup id {map_id} key {key_hex}"
    try:
        output = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL)
        lines = output.decode().strip().split('\n')
        for line in lines:
            if 'value:' in line:
                hex_part = line.split('value:')[1].strip()
                return bytes.fromhex(hex_part.replace(' ', ''))
        raise RuntimeError("Value not found in output")
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Failed to read map: {e}")

def write_map(map_name: str, key_hex: str, value_hex: str):
    """Write a value to a BPF map. Both are space‑separated hex strings."""
    map_id = get_map_id(map_name)
    cmd = f"bpftool map update id {map_id} key {key_hex} value {value_hex}"
    subprocess.run(cmd, shell=True, check=True)

def pin_map(map_name: str, pin_path: str):
    """Pin map for persistence."""
    try:
        subprocess.run(f"bpftool map pin name {map_name} {pin_path}", shell=True, check=True)
    except subprocess.CalledProcessError:
        pass  # already pinned

def int_to_hex(value: int, bytes_len: int, byteorder: str = 'little') -> str:
    """Convert integer to space‑separated hex bytes."""
    return " ".join(f"{b:02x}" for b in value.to_bytes(bytes_len, byteorder))