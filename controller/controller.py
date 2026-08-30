#!/usr/bin/env python3
import yaml
import time
import sys
from ebpf_loader import attach_xdp, detach_xdp, update_config_map

def main():
    try:
        with open("config.yaml", "r") as f:
            config = yaml.safe_load(f)
    except FileNotFoundError:
        print("[ERROR] config.yaml not found. Please create it from the template.")
        sys.exit(1)

    print("=== eBPF-Agg Controller ===")
    interface = config.get("xdp_interface", "eth0")
    session_id = 0x12345678
    max_workers = config.get("max_workers", 8)

    if not attach_xdp(interface, obj_path="ebpf/aggregator.bpf.o"):
        print("[ERROR] XDP attachment failed. Exiting.")
        sys.exit(1)

    update_config_map(session_id, max_workers)

    print(f"[Controller] Session {session_id:08x} ready for {max_workers} workers.")
    print(f"[Controller] Aggregator IP: {config.get('aggregator_ip')}:{config.get('aggregator_port')}")
    print("Press Ctrl+C to detach XDP and exit.")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[Controller] Shutting down...")
    finally:
        detach_xdp(interface)
        print("[Controller] Done.")

if __name__ == "__main__":
    main()