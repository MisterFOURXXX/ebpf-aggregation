#!/usr/bin/env python3
import os, re, sys
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt

def find_file(name):
    here = os.path.dirname(os.path.abspath(__file__))
    for p in [os.path.join(here, name),
              os.path.join(here, '..', 'results', name)]:
        if os.path.exists(p): return p
    return None

def parse(path):
    with open(path) as f:
        t = f.read()
    m = re.search(r'CPU Utilization:\s*([\d.]+)', t)
    return float(m.group(1)) if m else None

p = find_file('cpu_results.txt')
if not p:
    print("ERROR: cpu_results.txt not found"); sys.exit(1)
v = parse(p)
if v is None:
    print("ERROR: could not parse CPU percent"); sys.exit(1)
print("Measured aggregator CPU: %.2f percent (of 1 core)" % v)

REF_EBPF = 4.5
REF_UDP  = 72.0

labels = ['eBPF/XDP\n(ALEPH ref.)',
          'UDP/NCCL\n(gRPC ref.)',
          'Python aggregator\n(this work, measured)']
values = [REF_EBPF, REF_UDP, v]
colors = ['#2ecc71', '#e74c3c', '#3498db']

fig, ax = plt.subplots(figsize=(8, 6))
bars = ax.bar(labels, values, color=colors, width=0.6)
for b, val in zip(bars, values):
    ax.text(b.get_x() + b.get_width()/2, val + 1.0,
            '%.1f percent' % val, ha='center', fontsize=12, fontweight='bold')
ax.set_ylabel('CPU Usage (percent)', fontsize=13)
ax.set_title('Aggregator CPU Utilization - Comparison', fontsize=13)
ax.set_ylim(0, 100)
ax.grid(axis='y', linestyle='--', alpha=0.4)
plt.tight_layout()
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cpu_plot.png')
plt.savefig(out, dpi=150)
print("Saved: " + out)
