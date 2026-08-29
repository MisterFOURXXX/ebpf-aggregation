# config_loader.py
import yaml
import os

DEFAULT_CONFIG = {
    "aggregator_ip": "192.168.1.100",
    "aggregator_port": 9999,
    "xdp_interface": "eth0",
    "max_workers": 8,
    "packet_payload_floats": 32,
    "session_timeout_sec": 30,
    "bpf_map_pin_path": "/sys/fs/bpf/ebpf_agg"
}

def load_config(path="config.yaml"):
    if not os.path.exists(path):
        print(f"[WARN] {path} not found, using defaults")
        return DEFAULT_CONFIG
    with open(path, "r") as f:
        cfg = yaml.safe_load(f)
    # Merge with defaults
    for k, v in DEFAULT_CONFIG.items():
        if k not in cfg:
            cfg[k] = v
    return cfg