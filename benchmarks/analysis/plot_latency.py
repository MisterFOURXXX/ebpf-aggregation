#!/usr/bin/env python3
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

def generate_plot(csv_file="latency_results.csv"):
    try:
        df = pd.read_csv(csv_file)
        sizes = df['size_bytes']
        y_ebpf = df['latency_us']
        plt.loglog(sizes, y_ebpf, 'o-', label='eBPF-Agg')
        plt.xlabel('Payload Size (bytes)')
        plt.ylabel('Latency (µs)')
        plt.title('Latency vs. Payload Size')
        plt.legend()
        plt.grid(True)
        plt.savefig('latency_plot.png')
    except FileNotFoundError:
        print("No data file found; skipping plot.")

if __name__ == "__main__":
    generate_plot()