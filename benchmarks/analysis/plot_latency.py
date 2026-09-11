#!/usr/bin/env python3
import os, sys, csv
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt

def find_csv(name):
    here = os.path.dirname(os.path.abspath(__file__))
    for p in [os.path.join(here, name),
              os.path.join(here, '..', 'results', name)]:
        if os.path.exists(p): return p
    return None

csv_path = find_csv('latency_results.csv')
if not csv_path:
    print("ERROR: latency_results.csv missing"); sys.exit(1)
print("Reading: " + csv_path)

sizes, means, medians, p95s = [], [], [], []
with open(csv_path) as f:
    for row in csv.DictReader(f):
        try:
            sizes.append(int(row['size_bytes']))
            means.append(float(row['mean_us']))
            medians.append(float(row['median_us']))
            p95s.append(float(row['p95_us']))
        except (KeyError, ValueError):
            pass

print("Loaded %d data points" % len(sizes))
for s, m in zip(sizes, means):
    print("  %d bytes -> %d us" % (s, int(m)))

plt.figure(figsize=(10, 6))
plt.loglog(sizes, means,   'o-',  label='mean',   color='#2ecc71', linewidth=2, markersize=8)
plt.loglog(sizes, medians, 's--', label='median', color='#3498db', linewidth=2, markersize=8)
plt.loglog(sizes, p95s,    '^-.', label='p95',    color='#e67e22', linewidth=2, markersize=8)
plt.xlabel('Payload Size (bytes)', fontsize=13)
plt.ylabel('Latency (us)', fontsize=13)
plt.title('AllReduce Latency vs Payload Size', fontsize=13)
plt.grid(True, which='both', linestyle='--', alpha=0.5)
plt.legend(fontsize=11)
plt.tight_layout()
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'latency_plot.png')
plt.savefig(out, dpi=150)
print("Saved: " + out)
