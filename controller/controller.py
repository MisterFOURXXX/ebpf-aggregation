# controller.py
import yaml
import time
import sys
from ebpf_loader import attach_xdp, detach_xdp, update_config_map

def main():
    with open("config.yaml", "r") as f:
        config = yaml.safe_load(f)

    print("=== eBPF-Agg Controller ===")
    session_id = 0x12345678  # Fixed for MVP

    # 1. Attach XDP program
    attach_xdp(config["xdp_interface"])

    # 2. Configure the session
    update_config_map(session_id, config["max_workers"])

    print(f"[Controller] Session {session_id:08x} ready for {config['max_workers']} workers.")
    print(f"[Controller] Aggregator IP: {config['aggregator_ip']}:{config['aggregator_port']}")
    print("Press Ctrl+C to detach XDP and exit.")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[Controller] Shutting down...")
    finally:
        detach_xdp(config["xdp_interface"])
        print("[Controller] Done.")

if __name__ == "__main__":
    main()