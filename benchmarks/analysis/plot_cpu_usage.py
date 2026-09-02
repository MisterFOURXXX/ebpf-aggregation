#!/usr/bin/env python3
import matplotlib.pyplot as plt
import pandas as pd

def generate_plot(csv_file="cpu_results.csv"):
    # Assume csv with columns: mode, cpu_usage
    try:
        df = pd.read_csv(csv_file)
        modes = df['mode']
        usage = df['cpu_usage']
        plt.bar(modes, usage)
        plt.ylabel('CPU Usage (%)')
        plt.title('CPU Utilization Comparison')
        plt.savefig('cpu_plot.png')
    except FileNotFoundError:
        print("Demo data: eBPF=4.5%, UDP=72%")
        plt.bar(['eBPF', 'UDP'], [4.5, 72])
        plt.ylabel('CPU Usage (%)')
        plt.title('CPU Utilization (Illustrative)')
        plt.savefig('cpu_plot.png')

if __name__ == "__main__":
    generate_plot()