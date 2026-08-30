import subprocess
import json
import os
import time

def attach_xdp(interface: str, obj_path: str = "ebpf/aggregator.bpf.o"):
    if is_xdp_attached(interface):
        print(f"[INFO] XDP already attached to {interface}, skipping.")
        return True
    cmd = f"sudo ip link set dev {interface} xdp obj {obj_path} sec xdp"
    try:
        subprocess.run(cmd, shell=True, check=True)
        print(f"[OK] XDP attached to {interface}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Failed to attach XDP: {e}")
        return False

def is_xdp_attached(interface: str) -> bool:
    try:
        result = subprocess.run(
            f"ip link show {interface} | grep -q 'xdp'",
            shell=True, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL
        )
        return result.returncode == 0
    except Exception:
        return False

def detach_xdp(interface: str):
    cmd = f"sudo ip link set dev {interface} xdp off"
    subprocess.run(cmd, shell=True, stderr=subprocess.DEVNULL)
    print(f"[OK] XDP detached from {interface}")

def get_map_id(map_name: str) -> int:
    result = subprocess.check_output(f"bpftool map show name {map_name} -jp", shell=True)
    data = json.loads(result)
    if isinstance(data, list) and len(data) > 0:
        return data[0]["id"]
    elif isinstance(data, dict):
        return data["id"]
    raise RuntimeError(f"Map {map_name} not found")

def delete_key(map_id: int, key_hex: str):
    """Delete a single key from the map."""
    subprocess.run(
        f"bpftool map delete id {map_id} key {key_hex}",
        shell=True, stderr=subprocess.DEVNULL
    )

def update_config_map(session_id: int, expected_workers: int):
    """
    Write expected worker count to config_map.
    Forces the correct key (78 56 34 12) and deletes any stale entry.
    """
    try:
        map_id = get_map_id("config_map")

        # Known keys: the correct one and the stale one (just in case)
        correct_key = "78 56 34 12"          # little-endian of 0x12345678
        stale_key   = "4e 38 22 0c"          # observed stale key

        # Delete both keys to ensure a clean slate
        delete_key(map_id, correct_key)
        delete_key(map_id, stale_key)

        # Write the correct entry
        val_hex = "04 00 00 00"  # 4 workers in little-endian
        cmd = f'bpftool map update id {map_id} key {correct_key} value {val_hex}'
        subprocess.run(cmd, shell=True, check=True)
        print(f"[OK] Config map updated: session {session_id:08x} -> {expected_workers} workers")
        print(f"    Key bytes: {correct_key}  (should be 78 56 34 12)")

        # Verify
        output = subprocess.check_output(
            f"bpftool map lookup id {map_id} key {correct_key}",
            shell=True, stderr=subprocess.DEVNULL
        )
        for line in output.decode().strip().split('\n'):
            if 'value:' in line:
                val_part = line.split('value:')[1].strip()
                read_bytes = bytes.fromhex(val_part.replace(' ', ''))
                read_val = int.from_bytes(read_bytes, 'little')
                if read_val == expected_workers:
                    print("[VERIFY] Map value matches expected.")
                else:
                    print(f"[WARN] Map value mismatch: got {read_val}, expected {expected_workers}")
                break

    except Exception as e:
        print(f"[ERROR] Failed to update config map: {e}")

def pin_map(map_name: str, pin_path: str):
    subprocess.run(f"bpftool map pin name {map_name} {pin_path}", shell=True)