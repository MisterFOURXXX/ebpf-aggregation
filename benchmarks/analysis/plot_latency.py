#!/usr/bin/env python3
# plot_latency.py - Generates Graph 1 (Latency vs Payload Size)
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

def generate_plot(csv_file="latency_results.csv"):
    try:
        df = pd.read_csv(csv_file)
        sizes = df['size_mb']
        y_ebpf = df['latency_ebpf_us']
        y_udp = df['latency_udp_us']
        y_nccl = df['latency_nccl_us'] if 'latency_nccl_us' in df else None
    except FileNotFoundError:
        print(f"[WARN] {csv_file} not found. Using demo data.")
        sizes = [0.001, 0.064, 1, 16, 64, 256]
        y_ebpf = [80, 85, 120, 800, 3000, 12000]
        y_udp = [250, 300, 1500, 15000, 60000, 240000]
        y_nccl = [200, 210, 800, 6000, 20000, 80000]

    plt.figure(figsize=(10, 6))
    plt.loglog(sizes, y_ebpf, 'o-', label='eBPF-Agg', color='#2ecc71', linewidth=3, markersize=10)
    plt.loglog(sizes, y_udp, 's--', label='Standard UDP', color='#e74c3c', linewidth=2, markersize=8)
    if y_nccl:
        plt.loglog(sizes, y_nccl, 'd-.', label='NCCL (GPU Direct)', color='#3498db', linewidth=2, markersize=8)

    plt.xlabel('Payload Size (MB)', fontsize=14)
    plt.ylabel('AllReduce Latency (µs)', fontsize=14)
    plt.title('Latency vs. Payload Size (8 Workers)', fontsize=16)
    plt.legend(fontsize=12)
    plt.grid(True, which="both", linestyle='--', alpha=0.6)
    plt.tight_layout()
    plt.savefig('latency_plot.png', dpi=150)
    print("[OK] Saved latency_plot.png")

if __name__ == "__main__":
    generate_plot()