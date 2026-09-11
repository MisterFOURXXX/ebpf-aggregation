#!/usr/bin/env python3
import os, sys, csv
from collections import defaultdict
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt

def find_csv(name):
    here = os.path.dirname(os.path.abspath(__file__))
    for p in [os.path.join(here, name),
              os.path.join(here, '..', 'results', name)]:
        if os.path.exists(p): return p
    return None

p = find_csv('scalability_results.csv')
if not p:
    print("ERROR: scalability_results.csv missing"); sys.exit(1)
print("Reading: " + p)

buckets = defaultdict(list)
with open(p) as f:
    for row in csv.DictReader(f):
        try:
            n   = int(row['num_workers'])
            lat = float(row['latency_us'])
            ok  = int(row['ok'])
            # Reject timeouts (>= 100 ms) and failed rows
            if lat < 100000 and ok > 0:
                buckets[n].append(lat)
        except (KeyError, ValueError):
            pass

if not buckets:
    print("ERROR: no valid scalability data"); sys.exit(1)

xs = sorted(buckets.keys())
ys = [sum(buckets[n]) / len(buckets[n]) for n in xs]

print("Data:")
for n, y in zip(xs, ys):
    print("  %d workers -> mean %d us (n=%d)" % (n, int(y), len(buckets[n])))

plt.figure(figsize=(10, 6))
plt.plot(xs, ys, 'o-', color='#2ecc71', linewidth=2.5, markersize=10)
for x, y in zip(xs, ys):
    plt.annotate('%d us' % int(y), (x, y), textcoords='offset points',
                 xytext=(0, 12), ha='center', fontsize=11)
plt.xlabel('Number of Concurrent Workers', fontsize=13)
plt.ylabel('Mean AllReduce Latency (us)', fontsize=13)
plt.title('Scalability - Userspace Aggregator (Python)', fontsize=13)
plt.grid(True, linestyle='--', alpha=0.5)
plt.tight_layout()
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'scalability_plot.png')
plt.savefig(out, dpi=150)
print("Saved: " + out)
