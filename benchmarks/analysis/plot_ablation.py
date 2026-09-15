#!/usr/bin/env python3
"""plot_ablation.py - 6-panel ablation report (OK / SKIP / MISS)."""
import argparse, csv, re
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors

SIZE_ORDER  = [64, 256, 1024, 4096, 16384, 65536, 262144, 1048576]
SIZE_LABELS = ["64B","256B","1KB","4KB","16KB","64KB","256KB","1MB"]
CANON_ORDER = ["A1","A2","A3","A4","A5-pkt16","A5-pkt32","A5-pkt64",
               "A6-w1","A6-w2","A6-w4","A6-w8"]
NAME_LABEL = {
    "A1":"A1 eBPF/XDP","A2":"A2 userspace","A3":"A3 XDP_PASS","A4":"A4 UDP echo",
    "A5-pkt16":"A5 pkt=16","A5-pkt32":"A5 pkt=32","A5-pkt64":"A5 pkt=64",
    "A6-w1":"A6 w=1","A6-w2":"A6 w=2","A6-w4":"A6 w=4","A6-w8":"A6 w=8",
}
COLORS = plt.cm.tab20(np.linspace(0, 1, 20))

# coverage states
OK, SKIP, MISS = 0, 1, 2
COVERAGE_CMAP = mcolors.ListedColormap(["#2ecc71", "#f1c40f", "#e74c3c"])


def parse_metadata(p):
    md = {}
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                md[k.strip()] = v.strip()
    return md


def parse_latency(p):
    out = {}
    if not p.exists() or p.stat().st_size == 0:
        return out
    with p.open() as f:
        for row in csv.reader(f):
            if not row or row[0].strip() == "size_bytes":
                continue
            try:
                out[int(row[0])] = float(row[1])
            except (ValueError, IndexError):
                continue
    return out


def parse_scal(p):
    out = {}
    if not p.exists() or p.stat().st_size == 0:
        return out
    bucket = {}
    with p.open() as f:
        for row in csv.reader(f):
            if not row or row[0].strip() in ("num_workers","aggregator",""):
                continue
            try:
                n, _, lat, ok = int(row[0]), int(row[1]), float(row[2]), int(row[3])
                if ok > 0:
                    bucket.setdefault(n, []).append(lat)
            except (ValueError, IndexError):
                continue
    return {n: float(np.mean(v)) for n, v in bucket.items()}


def parse_cpu(p):
    if not p.exists() or p.stat().st_size == 0:
        return None
    for line in p.read_text().splitlines():
        if "CPU Utilization" in line:
            m = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*%", line)
            if m:
                return float(m.group(1))
    return None


def collect(root):
    data = {}
    for d in sorted(Path(root).iterdir()):
        if not d.is_dir() or d.name.startswith("_"):
            continue
        data[d.name] = {
            "md":   parse_metadata(d / "metadata.txt"),
            "lat":  parse_latency(d / "latency_results.csv"),
            "scal": parse_scal(d / "scalability_results.csv"),
            "cpu":  parse_cpu(d / "cpu_results.txt"),
        }
    return data


def names_in_order(data):
    return [n for n in CANON_ORDER if n in data]


def panel_latency_lines(ax, data):
    any_data = False
    for i, name in enumerate(names_in_order(data)):
        lat = data[name]["lat"]
        if not lat:
            continue
        xs = [s for s in SIZE_ORDER if s in lat]
        ys = [lat[s] for s in xs]
        ax.plot(range(len(xs)), ys, marker="o", linewidth=1.5,
                color=COLORS[i % len(COLORS)],
                label=NAME_LABEL.get(name, name))
        any_data = True
    ax.set_xticks(range(len(SIZE_ORDER)))
    ax.set_xticklabels(SIZE_LABELS)
    ax.set_xlabel("Payload size"); ax.set_ylabel("Mean latency (us)")
    ax.set_title("Latency vs payload size (log-log)")
    ax.set_yscale("log"); ax.grid(True, which="both", alpha=0.3)
    if any_data:
        ax.legend(fontsize=7, ncol=2)
    else:
        ax.text(0.5, 0.5, "no data", ha="center", va="center",
                transform=ax.transAxes, color="grey")


def panel_heatmap(ax, data):
    names = names_in_order(data)
    M = np.full((len(names), len(SIZE_ORDER)), np.nan)
    for i, n in enumerate(names):
        for j, s in enumerate(SIZE_ORDER):
            if s in data[n]["lat"]:
                M[i, j] = data[n]["lat"][s]
    if M.size == 0 or np.all(np.isnan(M)):
        ax.text(0.5, 0.5, "no data", ha="center", va="center",
                transform=ax.transAxes, color="grey")
        ax.set_title("Latency heatmap (us, log scale)"); return
    Mlog = np.log10(np.where(np.isnan(M), np.nan, M))
    im = ax.imshow(Mlog, aspect="auto", cmap="viridis")
    ax.set_xticks(range(len(SIZE_ORDER)))
    ax.set_xticklabels(SIZE_LABELS)
    ax.set_yticks(range(len(names)))
    ax.set_yticklabels([NAME_LABEL.get(n, n) for n in names])
    for i in range(M.shape[0]):
        for j in range(M.shape[1]):
            if not np.isnan(M[i, j]):
                ax.text(j, i, f"{M[i,j]:.0f}", ha="center", va="center",
                        fontsize=6, color="white")
    ax.set_title("Latency heatmap (us, log scale)")
    plt.colorbar(im, ax=ax, fraction=0.045, label="log10(us)")


def panel_cpu(ax, data):
    # We show all canonical configs; those without a CPU value but with
    # cpu_skipped=multi-worker get a grey "skip" bar of height 0.
    present = []
    for n in names_in_order(data):
        d = data[n]
        if d["cpu"] is not None:
            present.append((n, d["cpu"], False))
        elif d["md"].get("cpu_skipped"):
            present.append((n, None, True))
    if not present:
        ax.text(0.5, 0.5, "no data", ha="center", va="center",
                transform=ax.transAxes, color="grey")
        ax.set_title("Aggregator CPU utilization"); return
    labels = [NAME_LABEL.get(n, n) for n, _, _ in present]
    vals   = [v if v is not None else 0 for _, v, _ in present]
    colors = ["#bbbbbb" if s else COLORS[i % len(COLORS)]
              for i, (_, _, s) in enumerate(present)]
    bars = ax.bar(range(len(labels)), vals, color=colors)
    for b, (_, v, s) in zip(bars, present):
        if s:
            ax.text(b.get_x() + b.get_width()/2, 0.4, "skip",
                    ha="center", va="bottom", fontsize=8, color="#444")
        else:
            ax.text(b.get_x() + b.get_width()/2, v + 0.3, f"{v:.1f}",
                    ha="center", va="bottom", fontsize=8)
    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
    ax.set_ylabel("CPU (% of one core)")
    ax.set_title("Aggregator CPU utilization (grey = skipped by design)")


def panel_scalability(ax, data):
    any_data = False
    for i, name in enumerate(names_in_order(data)):
        scal = data[name]["scal"]
        if not scal:
            continue
        xs = sorted(scal.keys()); ys = [scal[x] for x in xs]
        ax.plot(xs, ys, marker="s", linewidth=1.5,
                color=COLORS[i % len(COLORS)],
                label=NAME_LABEL.get(name, name))
        any_data = True
    ax.set_xlabel("Number of workers"); ax.set_ylabel("Mean latency (us)")
    ax.set_title("Scalability (mean latency vs workers)")
    ax.set_yscale("log"); ax.grid(True, which="both", alpha=0.3)
    if any_data:
        ax.legend(fontsize=7, ncol=2)
    else:
        ax.text(0.5, 0.5, "no data", ha="center", va="center",
                transform=ax.transAxes, color="grey")


def panel_coverage(ax, data):
    names = names_in_order(data)
    if not names:
        ax.text(0.5, 0.5, "no data", ha="center", va="center",
                transform=ax.transAxes, color="grey")
        ax.set_title("Coverage"); return
    cols = ["status","latency","scal","cpu"]
    M = np.zeros((len(names), len(cols)), dtype=int)
    for i, n in enumerate(names):
        d = data[n]
        # status
        M[i, 0] = OK if d["md"].get("status") == "ok" else MISS
        # latency
        if d["lat"]:
            M[i, 1] = OK
        elif d["md"].get("latency_skipped"):
            M[i, 1] = SKIP
        else:
            M[i, 1] = MISS
        # scalability
        M[i, 2] = OK if d["scal"] else MISS
        # cpu
        if d["cpu"] is not None:
            M[i, 3] = OK
        elif d["md"].get("cpu_skipped"):
            M[i, 3] = SKIP
        else:
            M[i, 3] = MISS
    ax.imshow(M, aspect="auto", cmap=COVERAGE_CMAP, vmin=0, vmax=2)
    ax.set_xticks(range(len(cols))); ax.set_xticklabels(cols)
    ax.set_yticks(range(len(names)))
    ax.set_yticklabels([NAME_LABEL.get(n, n) for n in names])
    for i in range(M.shape[0]):
        for j in range(M.shape[1]):
            ax.text(j, i, {OK:"OK", SKIP:"SKIP", MISS:"MISS"}[M[i,j]],
                    ha="center", va="center", fontsize=7, color="black")
    ax.set_title("Coverage (OK / SKIP / MISS)")


def panel_table(ax, data):
    ax.axis("off")
    names = names_in_order(data)
    rows = [["ablation","status","lat","scal","cpu","cpu%","mean_lat"]]
    for n in names:
        d = data[n]; lat = d["lat"]
        mean_lat = f"{np.mean(list(lat.values())):.1f}" if lat else "-"
        cpu      = f"{d['cpu']:.1f}" if d["cpu"] is not None else "-"
        rows.append([
            NAME_LABEL.get(n, n),
            d["md"].get("status","?"),
            str(len(lat)),
            str(len(d["scal"])),
            "skip" if d["md"].get("cpu_skipped") else
            ("yes" if d["cpu"] is not None else "-"),
            cpu, mean_lat,
        ])
    if len(rows) == 1:
        ax.text(0.5, 0.5, "no data", ha="center", va="center",
                transform=ax.transAxes, color="grey")
        ax.set_title("Summary table"); return
    t = ax.table(cellText=rows, loc="center", cellLoc="left")
    t.auto_set_font_size(False); t.set_fontsize(7); t.scale(1, 1.4)
    ax.set_title("Summary table")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input",  required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    out = Path(args.output); out.mkdir(parents=True, exist_ok=True)
    data = collect(args.input)
    if not data:
        print("No ablation directories found under", args.input); return

    print(f"Found {len(data)} ablation configurations")
    for n in CANON_ORDER:
        if n in data:
            d = data[n]
            cpu_s = "yes" if d["cpu"] is not None else \
                    ("skip" if d["md"].get("cpu_skipped") else "no")
            print(f"  {n:<10} status={d['md'].get('status','?'):<14} "
                  f"lat={len(d['lat'])} scal={len(d['scal'])} cpu={cpu_s}")

    fig, axes = plt.subplots(3, 2, figsize=(16, 14))
    fig.suptitle("eBPF-P4 Aggregation - Ablation Study Report",
                 fontsize=14, fontweight="bold")
    panel_latency_lines(axes[0, 0], data)
    panel_heatmap    (axes[0, 1], data)
    panel_cpu        (axes[1, 0], data)
    panel_scalability(axes[1, 1], data)
    panel_coverage   (axes[2, 0], data)
    panel_table      (axes[2, 1], data)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    png = out / "ablation_report.png"
    fig.savefig(png, dpi=120); plt.close(fig)
    print("Saved:", png)


if __name__ == "__main__":
    main()