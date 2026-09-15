#!/usr/bin/env python3
"""
Analyze ablation results: build comparison table + plots (ASCII-only output).
"""
import os, sys, csv, re, glob
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE    = os.path.dirname(os.path.abspath(__file__))
ROOT    = os.path.abspath(os.path.join(HERE, '..', '..'))
RESULTS = os.path.join(ROOT, 'benchmarks', 'results', 'ablation')
REPORT  = os.path.join(RESULTS, '_report')
os.makedirs(REPORT, exist_ok=True)


def read_metadata(d):
    meta = {}
    p = os.path.join(d, 'metadata.txt')
    if not os.path.exists(p):
        return meta
    with open(p) as f:
        for line in f:
            line = line.strip()
            if '=' in line:
                k, v = line.split('=', 1)
                meta[k] = v
    return meta


def parse_latency_csv(path):
    out = {}
    if not os.path.exists(path):
        return out
    with open(path) as f:
        for row in csv.DictReader(f):
            try:
                size = int(row.get('size_bytes', row.get('size_mb', 0)))
                lat  = float(row.get('mean_us', row.get('latency_us', 0)))
                if size > 0 and lat > 0:
                    out[size] = lat
            except (KeyError, ValueError):
                pass
    return out


def parse_cpu_txt(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        txt = f.read()
    m = re.search(r'CPU Utilization:\s*([\d.]+)', txt)
    return float(m.group(1)) if m else None


def parse_scalability_csv(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path) as f:
        for row in csv.DictReader(f):
            try:
                wid = int(row.get('worker_id', 0))
                lat = float(row.get('latency_us', 0))
                ok  = row.get('ok', '?')
                if lat > 0 and lat < 100000:
                    rows.append((wid, lat, ok))
            except (KeyError, ValueError):
                pass
    return rows


def collect():
    recs = []
    for d in sorted(glob.glob(os.path.join(RESULTS, '*'))):
        if not os.path.isdir(d) or os.path.basename(d).startswith('_'):
            continue
        meta = read_metadata(d)
        if not meta:
            continue
        recs.append({
            'id':         meta.get('ABLATION_ID', os.path.basename(d)),
            'name':       meta.get('ABLATION_NAME', ''),
            'latency':    parse_latency_csv(os.path.join(d, 'latency_results.csv')),
            'cpu':        parse_cpu_txt(os.path.join(d, 'cpu_results.txt')),
            'scalability': parse_scalability_csv(os.path.join(d, 'scalability_results.csv')),
            'workers':    meta.get('NUM_WORKERS', '?'),
            'pkt_floats': meta.get('PKT_FLOATS', '?'),
        })
    return recs


def print_table(recs):
    print()
    print("=" * 90)
    print("ABLATION COMPARISON TABLE")
    print("=" * 90)

    sizes = sorted({s for r in recs for s in r['latency']})
    if sizes:
        print("\n-- Latency (us) by payload size --")
        header = "%-12s %-30s " % ("Ablation", "Name")
        header += " ".join("%9d" % s for s in sizes)
        print(header)
        print("-" * len(header))
        for r in recs:
            row = "%-12s %-30s " % (r['id'][:12], r['name'][:30])
            for s in sizes:
                v = r['latency'].get(s)
                row += "%9.0f " % v if v is not None else "%9s " % "-"
            print(row)

    print("\n-- CPU Util & Scalability --")
    header2 = "%-12s %-30s %8s %15s %10s" % (
        "Ablation", "Name", "CPU %", "Avg Scal (us)", "Wkrs OK")
    print(header2)
    print("-" * len(header2))
    for r in recs:
        cpu = "%.1f" % r['cpu'] if r['cpu'] is not None else "-"
        scal = r['scalability']
        if scal:
            avg = sum(l for _, l, _ in scal) / len(scal)
            n_ok = sum(1 for _, _, ok in scal if ok.endswith("/10"))
            scal_s = "%.0f" % avg
            ok_s   = "%d/%d" % (n_ok, len(scal))
        else:
            scal_s = "-"
            ok_s   = "-"
        print("%-12s %-30s %8s %15s %10s" %
              (r['id'][:12], r['name'][:30], cpu, scal_s, ok_s))
    print()


def plot_latency(recs):
    sizes = sorted({s for r in recs for s in r['latency']})
    recs = [r for r in recs if r['latency']]
    if not sizes or not recs:
        return
    n = len(recs)
    bar_w = 0.8 / n
    x = list(range(len(sizes)))
    fig, ax = plt.subplots(figsize=(max(10, len(sizes) * 1.8), 6))
    colors = plt.cm.tab10.colors
    for i, r in enumerate(recs):
        ys = [r['latency'].get(s, 0) for s in sizes]
        xs = [xi + i * bar_w - 0.4 + bar_w / 2 for xi in x]
        ax.bar(xs, ys, width=bar_w, label=r['id'], color=colors[i % len(colors)])
    ax.set_xticks(x)
    ax.set_xticklabels([str(s) for s in sizes])
    ax.set_xlabel('Payload Size (bytes)')
    ax.set_ylabel('Latency (us)')
    ax.set_title('Ablation: Latency by Payload Size')
    ax.set_yscale('log')
    ax.grid(axis='y', which='both', linestyle='--', alpha=0.4)
    ax.legend(fontsize=9, ncol=2)
    plt.tight_layout()
    out = os.path.join(REPORT, 'ablation_latency_comparison.png')
    plt.savefig(out, dpi=150)
    plt.close()
    print("Saved: " + out)


def plot_cpu(recs):
    recs = [r for r in recs if r['cpu'] is not None]
    if not recs:
        return
    fig, ax = plt.subplots(figsize=(max(8, len(recs) * 1.2), 6))
    ids = [r['id'] for r in recs]
    cpu = [r['cpu'] for r in recs]
    colors = plt.cm.tab10.colors[:len(recs)]
    bars = ax.bar(ids, cpu, color=colors)
    for b, v in zip(bars, cpu):
        ax.text(b.get_x() + b.get_width()/2, v + 1,
                "%.1f" % v, ha='center', fontsize=10)
    ax.set_ylabel('CPU Utilization (percent)')
    ax.set_title('Ablation: CPU Utilization')
    ax.set_ylim(0, 100)
    ax.grid(axis='y', linestyle='--', alpha=0.4)
    plt.xticks(rotation=20, ha='right')
    plt.tight_layout()
    out = os.path.join(REPORT, 'ablation_cpu_comparison.png')
    plt.savefig(out, dpi=150)
    plt.close()
    print("Saved: " + out)


def plot_scalability(recs):
    recs = [r for r in recs if r['scalability']]
    if not recs:
        return
    fig, ax = plt.subplots(figsize=(max(8, len(recs) * 1.4), 6))
    for i, r in enumerate(recs):
        pairs = sorted(r['scalability'])
        xs = [w + i * 0.15 for w, _, _ in pairs]
        ys = [l for _, l, _ in pairs]
        ax.bar(xs, ys, width=0.15, label=r['id'])
    ax.set_xlabel('Worker ID')
    ax.set_ylabel('Latency (us)')
    ax.set_title('Ablation: Per-Worker Latency')
    ax.legend(fontsize=9, ncol=3)
    ax.grid(axis='y', linestyle='--', alpha=0.4)
    plt.tight_layout()
    out = os.path.join(REPORT, 'ablation_scalability_comparison.png')
    plt.savefig(out, dpi=150)
    plt.close()
    print("Saved: " + out)


def write_csv(recs):
    sizes = sorted({s for r in recs for s in r['latency']})
    out = os.path.join(REPORT, 'ablation_summary.csv')
    with open(out, 'w', newline='') as f:
        w = csv.writer(f)
        header = ['ablation_id', 'name', 'cpu_pct', 'workers', 'pkt_floats']
        header += ['latency_%dB_us' % s for s in sizes]
        w.writerow(header)
        for r in recs:
            row = [r['id'], r['name'],
                   r['cpu'] if r['cpu'] is not None else '',
                   r['workers'], r['pkt_floats']]
            for s in sizes:
                row.append(r['latency'].get(s, ''))
            w.writerow(row)
    print("Saved: " + out)


def main():
    recs = collect()
    if not recs:
        print("ERROR: no ablation results found in " + RESULTS)
        sys.exit(1)

    print("Found %d ablation configurations" % len(recs))
    print_table(recs)
    write_csv(recs)
    plot_latency(recs)
    plot_cpu(recs)
    plot_scalability(recs)
    print("")
    print("Reports saved under: " + REPORT)


if __name__ == '__main__':
    main()
