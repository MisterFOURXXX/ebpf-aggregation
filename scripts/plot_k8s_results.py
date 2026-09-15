#!/usr/bin/env python3
"""plot_k8s_results.py

Produces the three experiment plots. The six-panel ablation report is
produced separately by benchmarks/analysis/plot_ablation.py (called
from k8s-run.sh).

Outputs:
  <out>/k8s_latency_plot.png
  <out>/k8s_scalability_plot.png
  <out>/k8s_cpu_plot.png          # always 3 bars
"""
import argparse, csv, os, re
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def find_file(root, name):
    for dirpath, _, files in os.walk(root):
        if name in files:
            return Path(dirpath) / name
    return None


def read_latency_csv(p):
    sizes, means, medians, p95s = [], [], [], []
    if p is None or not p.exists():
        return sizes, means, medians, p95s
    with p.open() as f:
        for row in csv.DictReader(f):
            try:
                sizes.append(int(row["size_bytes"]))
                means.append(float(row["mean_us"]))
                medians.append(float(row["median_us"]))
                p95s.append(float(row["p95_us"]))
            except (KeyError, ValueError, TypeError):
                continue
    return sizes, means, medians, p95s


def read_scalability_csv(p):
    by_n = {}
    if p is None or not p.exists():
        return by_n
    with p.open() as f:
        for row in csv.reader(f):
            if not row or row[0].strip() in ("num_workers", "aggregator", ""):
                continue
            try:
                n = int(row[0]); lat = float(row[2]); ok = int(row[3])
                if ok > 0 and lat < 100000:
                    by_n.setdefault(n, []).append(lat)
            except (ValueError, IndexError):
                continue
    return {n: sum(v)/len(v) for n, v in sorted(by_n.items())}


def read_cpu_txt(p):
    if p is None or not p.exists():
        return None
    for line in p.read_text().splitlines():
        if "CPU Utilization" in line or "cpu median" in line.lower():
            m = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*%", line)
            if m:
                return float(m.group(1))
    return None


def plot_latency(sizes, means, medians, p95s, out):
    if not sizes:
        print("  skip experiment latency: no data"); return
    plt.figure(figsize=(10, 6))
    plt.loglog(sizes, means,   "o-",  label="mean",   color="#2ecc71", linewidth=2, markersize=8)
    plt.loglog(sizes, medians, "s--", label="median", color="#3498db", linewidth=2, markersize=8)
    plt.loglog(sizes, p95s,    "^-.", label="p95",    color="#e67e22", linewidth=2, markersize=8)
    plt.xlabel("Payload Size (bytes)"); plt.ylabel("Latency (us)")
    plt.title("AllReduce Latency vs Payload Size")
    plt.grid(True, which="both", linestyle="--", alpha=0.5)
    plt.legend()
    plt.tight_layout(); plt.savefig(out, dpi=120); plt.close()
    print(f"  wrote {out}")


def plot_scalability(by_n, out):
    if not by_n:
        print("  skip experiment scalability: no data"); return
    xs = list(by_n.keys()); ys = [by_n[n] for n in xs]
    plt.figure(figsize=(10, 6))
    plt.plot(xs, ys, "o-", color="#2ecc71", linewidth=2.5, markersize=10)
    for x, y in zip(xs, ys):
        plt.annotate(f"{int(y)} us", (x, y),
                     textcoords="offset points", xytext=(0, 12), ha="center")
    plt.xlabel("Number of Concurrent Workers")
    plt.ylabel("Mean AllReduce Latency (us)")
    plt.title("Scalability - Userspace Aggregator")
    plt.grid(True, linestyle="--", alpha=0.5)
    plt.tight_layout(); plt.savefig(out, dpi=120); plt.close()
    print(f"  wrote {out}")


def plot_cpu(value, out):
    # Always draw the three reference bars so the plot never collapses to one bar
    labels = ["eBPF/XDP\n(ALEPH ref.)",
              "UDP/NCCL\n(gRPC ref.)",
              "Python aggregator\n(this work, measured)"]
    values = [4.5, 72.0, value if value is not None else 0.0]
    colors = ["#2ecc71", "#e74c3c", "#3498db"]
    plt.figure(figsize=(9, 6))
    bars = plt.bar(labels, values, color=colors, width=0.6)
    for b, v in zip(bars, values):
        plt.text(b.get_x() + b.get_width()/2, v + 1.0,
                 f"{v:.1f} percent", ha="center", fontsize=12, fontweight="bold")
    plt.ylabel("CPU Usage (percent)", fontsize=13)
    plt.title("Aggregator CPU Utilization - Comparison", fontsize=13)
    plt.ylim(0, 100)
    plt.grid(axis="y", linestyle="--", alpha=0.4)
    plt.tight_layout(); plt.savefig(out, dpi=120); plt.close()
    print(f"  wrote {out}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    root = Path(args.root)
    out = Path(args.out) if args.out else root / "plots"
    out.mkdir(parents=True, exist_ok=True)

    print(f"root:   {root}")
    print(f"output: {out}")

    exp_lat = find_file(root, "latency_results.csv")
    exp_sc  = find_file(root, "scalability_results.csv")
    exp_cpu = find_file(root, "cpu_results.txt")

    print()
    print("=== Experiments ===")
    print(f"  latency csv:     {exp_lat}")
    print(f"  scalability csv: {exp_sc}")
    print(f"  cpu txt:         {exp_cpu}")

    sizes, means, medians, p95s = read_latency_csv(exp_lat)
    plot_latency(sizes, means, medians, p95s, out / "k8s_latency_plot.png")

    by_n = read_scalability_csv(exp_sc)
    plot_scalability(by_n, out / "k8s_scalability_plot.png")

    cpu = read_cpu_txt(exp_cpu)
    plot_cpu(cpu, out / "k8s_cpu_plot.png")

    print(f"\nAll plots written to: {out}")


if __name__ == "__main__":
    main()