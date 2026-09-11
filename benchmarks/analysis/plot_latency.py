#!/usr/bin/env python3
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
import os
import sys

def generate_plot(csv_file="latency_results.csv"):
    # Check if file exists
    if not os.path.exists(csv_file):
        # Try to find the actual benchmark output
        alt_file = "../build/latency_results.csv"
        if os.path.exists(alt_file):
            csv_file = alt_file
        else:
            print(f"No data file found. Run latency_benchmark first.")
            print("Demo data shown below:")
            sizes = [64, 256, 1024, 4096, 16384]
            y = [1862, 2247, 2825, 7820, 13556]
            plt.loglog(sizes, y, 'o-', label='eBPF-Agg (demo)', linewidth=2, markersize=10)
            plt.xlabel('Payload Size (bytes)', fontsize=14)
            plt.ylabel('Latency (µs)', fontsize=14)
            plt.title('Latency vs. Payload Size (Demo Data)', fontsize=16)
            plt.grid(True, linestyle='--', alpha=0.6)
            plt.legend(fontsize=12)
            plt.tight_layout()
            plt.savefig('latency_plot.png')
            print("[OK] Saved latency_plot.png (demo)")
            return

    try:
        df = pd.read_csv(csv_file)
        # Check if columns exist
        if 'size_bytes' in df.columns and 'latency_us' in df.columns:
            sizes = df['size_bytes']
            y = df['latency_us']
            plt.loglog(sizes, y, 'o-', label='eBPF-Agg', linewidth=2, markersize=10)
            plt.xlabel('Payload Size (bytes)', fontsize=14)
            plt.ylabel('Latency (µs)', fontsize=14)
            plt.title('Latency vs. Payload Size', fontsize=16)
            plt.grid(True, linestyle='--', alpha=0.6)
            plt.legend(fontsize=12)
            plt.tight_layout()
            plt.savefig('latency_plot.png')
            print("[OK] Saved latency_plot.png")
        else:
            print(f"CSV columns: {df.columns.tolist()}")
    except Exception as e:
        print(f"Error reading {csv_file}: {e}")

if __name__ == "__main__":
    generate_plot()
