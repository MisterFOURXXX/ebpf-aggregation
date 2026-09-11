#!/usr/bin/env python3
import matplotlib.pyplot as plt
import pandas as pd
import os

def generate_plot(csv_file="scalability_results.csv"):
    if not os.path.exists(csv_file):
        alt_file = "../build/scalability_results.csv"
        if os.path.exists(alt_file):
            csv_file = alt_file
        else:
            print("[WARN] No data file found. Using demo data.")
            x = [2, 4, 8, 16]
            y_ebpf = [85, 87, 90, 95]
            y_udp = [600, 1100, 2200, 4400]
            plt.plot(x, y_ebpf, 'o-', label='eBPF-Agg', color='#2ecc71', linewidth=3, markersize=10)
            plt.plot(x, y_udp, 's--', label='Standard UDP', color='#e74c3c', linewidth=2, markersize=8)
            plt.xlabel('Number of Workers', fontsize=14)
            plt.ylabel('AllReduce Latency (µs)', fontsize=14)
            plt.title('Scalability: Latency vs. Worker Count (Demo)', fontsize=16)
            plt.legend(fontsize=12)
            plt.grid(True, linestyle='--', alpha=0.6)
            plt.yscale('log')
            plt.tight_layout()
            plt.savefig('scalability_plot.png', dpi=150)
            print("[OK] Saved scalability_plot.png (demo)")
            return

    try:
        df = pd.read_csv(csv_file)
        if 'workers' in df.columns and 'latency_ebpf' in df.columns:
            x = df['workers']
            y_ebpf = df['latency_ebpf']
            plt.plot(x, y_ebpf, 'o-', label='eBPF-Agg', color='#2ecc71', linewidth=3, markersize=10)
            plt.xlabel('Number of Workers', fontsize=14)
            plt.ylabel('AllReduce Latency (µs)', fontsize=14)
            plt.title('Scalability: Latency vs. Worker Count', fontsize=16)
            plt.legend(fontsize=12)
            plt.grid(True, linestyle='--', alpha=0.6)
            plt.tight_layout()
            plt.savefig('scalability_plot.png', dpi=150)
            print("[OK] Saved scalability_plot.png")
        else:
            print(f"CSV columns: {df.columns.tolist()}")
    except Exception as e:
        print(f"Error reading {csv_file}: {e}")

if __name__ == "__main__":
    generate_plot()
