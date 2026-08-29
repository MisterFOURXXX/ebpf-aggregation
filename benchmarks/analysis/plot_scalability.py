#!/usr/bin/env python3
# plot_scalability.py - Generates Graph 2 (Latency vs Number of Workers)
import matplotlib.pyplot as plt
import pandas as pd
import sys
import os

# Example data structure - in reality, you'd read from CSV/Logs
# Expected CSV: workers,latency_ebpf,latency_udp
def generate_plot(csv_file="scalability_results.csv"):
    try:
        df = pd.read_csv(csv_file)
        x = df['workers']
        y_ebpf = df['latency_ebpf']
        y_udp = df['latency_udp']
    except FileNotFoundError:
        # Demo data if file doesn't exist yet
        print(f"[WARN] {csv_file} not found. Using demo data.")
        x = [2, 4, 8, 16]
        y_ebpf = [85, 87, 90, 95]   # eBPF scales nearly flat
        y_udp = [600, 1100, 2200, 4400]  # UDP scales linearly

    plt.figure(figsize=(10, 6))
    plt.plot(x, y_ebpf, 'o-', label='eBPF-Agg (XDP)', color='#2ecc71', linewidth=3, markersize=10)
    plt.plot(x, y_udp, 's--', label='Standard UDP (Kernel)', color='#e74c3c', linewidth=2, markersize=8)

    plt.xlabel('Number of Workers', fontsize=14)
    plt.ylabel('AllReduce Latency (µs)', fontsize=14)
    plt.title('Scalability: Latency vs. Worker Count (Payload: 1MB)', fontsize=16)
    plt.legend(fontsize=12)
    plt.grid(True, linestyle='--', alpha=0.6)
    plt.yscale('log')  # Log scale highlights the linear vs constant scaling
    plt.tight_layout()
    plt.savefig('scalability_plot.png', dpi=150)
    print("[OK] Saved scalability_plot.png")

if __name__ == "__main__":
    generate_plot()