# plot_cpu_usage.py
import matplotlib.pyplot as plt
import numpy as np

labels = ['eBPF-Agg', 'Standard UDP', 'NCCL']
cpu_usage = [5, 72, 45]  # Example data

plt.figure(figsize=(8, 5))
bars = plt.bar(labels, cpu_usage, color=['#2ecc71', '#e74c3c', '#f39c12'])
plt.ylabel('CPU Utilization (%)')
plt.title('Aggregator CPU Usage During AllReduce (64MB)')
plt.ylim(0, 100)
for bar, val in zip(bars, cpu_usage):
    plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 2, f'{val}%', ha='center')
plt.grid(axis='y', linestyle='--', alpha=0.7)
plt.savefig('cpu_usage_comparison.png', dpi=150)
print("Saved cpu_usage_comparison.png")