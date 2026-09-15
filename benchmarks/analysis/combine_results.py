#!/usr/bin/env python3
"""Combine per-ablation results into 4 CSV files.

Handles three CPU output formats that can appear in cpu_results.txt:

  1. median-of-N (newest):
        run 1: cpu=34.0516 wall=0.146836
        ...
        cpu median: 34.0516 %  total wall: 0.696100 s

  2. single-run (older):
        Aggregator CPU time:  0.05 s
        Wall time:            0.14088 s
        CPU Utilization:      35.4912 %  (of 1 core)

  3. broken (skip):
        Aggregator CPU time:   s  (sum of 10 runs)

For multi-worker configs (A6-w2/w4/w8), latency and CPU are
intentionally absent - the benchmarks are single-client. These are
recorded as 'skipped_multi_worker', not as failures.
"""
import argparse, csv, re
from pathlib import Path
import statistics as st

CANON = ["A1","A2","A3","A4","A5-pkt16","A5-pkt32","A5-pkt64",
         "A6-w1","A6-w2","A6-w4","A6-w8"]

SHORT_WINDOW_S = 1.0   # below this the CPU number is noisy


def parse_metadata(p):
    md = {}
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                md[k.strip()] = v.strip()
    return md


def parse_latency(p):
    """Return (rows, fail_count)."""
    rows, fails = [], 0
    if not p.exists() or p.stat().st_size == 0:
        return rows, fails
    with p.open() as f:
        for row in csv.reader(f):
            if not row or row[0].strip() == "size_bytes":
                continue
            if any(v.strip().upper() == "FAIL" for v in row[1:]):
                fails += 1
                continue
            try:
                rows.append({
                    "size_bytes": int(row[0]),
                    "mean_us":    float(row[1]),
                    "median_us":  float(row[2]),
                    "p95_us":     float(row[3]),
                    "trimmed_us": float(row[4]),
                })
            except (ValueError, IndexError):
                fails += 1
                continue
    return rows, fails


def parse_scal(p):
    rows = []
    if not p.exists() or p.stat().st_size == 0:
        return rows
    with p.open() as f:
        for row in csv.reader(f):
            if not row or row[0].strip() in ("num_workers", "aggregator", ""):
                continue
            try:
                rows.append({
                    "num_workers": int(row[0]),
                    "worker_id":   int(row[1]),
                    "latency_us":  float(row[2]),
                    "ok":          int(row[3]),
                })
            except (ValueError, IndexError):
                continue
    return rows


def parse_cpu_window(p):
    """Return (cpu_percent, wall_time_s, format_tag) or (None, None, None).

    format_tag is one of:
      'median' - median-of-N runs
      'single' - single-run output
      None     - unparseable (broken output)
    """
    if not p.exists() or p.stat().st_size == 0:
        return None, None, None
    txt = p.read_text()

    # -------- format 1: median-of-N --------
    # "cpu median: 34.0516 %  total wall: 0.696100 s"
    m = re.search(
        r"cpu\s+median:\s*([0-9]+(?:\.[0-9]+)?)\s*%\s*"
        r"total\s+wall:\s*([0-9]+(?:\.[0-9]+)?)\s*s",
        txt,
    )
    if m:
        return float(m.group(1)), float(m.group(2)), "median"

    # -------- format 2: single-run --------
    pct_m  = re.search(r"CPU Utilization:\s*([0-9]+(?:\.[0-9]+)?)\s*%", txt)
    wall_m = re.search(r"Wall time:\s*([0-9]+(?:\.[0-9]+)?)\s*s", txt)
    if pct_m and wall_m:
        return float(pct_m.group(1)), float(wall_m.group(1)), "single"

    # -------- format 3: broken output, e.g. "Aggregator CPU time:  s" --------
    # Deliberately return None so the summary column is empty
    return None, None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input",  required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    root = Path(args.input)
    out  = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)

    summary, lat_all, scal_all, cpu_all = [], [], [], []

    for d in sorted(root.iterdir()):
        if not d.is_dir() or d.name.startswith("_"):
            continue

        md            = parse_metadata(d / "metadata.txt")
        lat, lat_fail = parse_latency (d / "latency_results.csv")
        scal          = parse_scal    (d / "scalability_results.csv")
        cpu_pct, cpu_wall, cpu_fmt = parse_cpu_window(d / "cpu_results.txt")

        workers  = int(md.get("workers", "1") or 1)
        mean_lat = round(st.mean(r["mean_us"] for r in lat), 2) if lat else ""

        # Classify the CPU cell
        if cpu_pct is not None:
            cpu_field = cpu_pct
        elif workers > 1:
            cpu_field = "skipped_multi_worker"
        else:
            cpu_field = ""      # measurement failed or broken output

        # Only meaningful when a number was measured
        if cpu_wall is not None and cpu_wall < SHORT_WINDOW_S:
            cpu_warn = "short_window"
        else:
            cpu_warn = ""

        summary.append({
            "ablation":        d.name,
            "type":            md.get("type", ""),
            "status":          md.get("status", "unknown"),
            "workers":         workers,
            "pkt_floats":      md.get("pkt_floats", ""),
            "sizes":           md.get("sizes", ""),
            "n_ok":            len(lat),
            "n_fail":          lat_fail,
            "mean_latency_us": mean_lat,
            "cpu_percent":     cpu_field,
            "cpu_wall_s":      cpu_wall if cpu_wall is not None else "",
            "cpu_fmt":         cpu_fmt if cpu_fmt else "",
            "cpu_warn":        cpu_warn,
        })

        for r in lat:
            lat_all.append({"ablation": d.name, **r})
        for r in scal:
            scal_all.append({"ablation": d.name, **r})
        if cpu_pct is not None:
            cpu_all.append({
                "ablation":   d.name,
                "cpu_percent": cpu_pct,
                "cpu_wall_s":  cpu_wall if cpu_wall is not None else "",
                "cpu_fmt":     cpu_fmt   if cpu_fmt  else "",
            })

    summary.sort(key=lambda r: CANON.index(r["ablation"])
                 if r["ablation"] in CANON else 999)

    def dump(path, rows, fields):
        with path.open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields)
            w.writeheader(); w.writerows(rows)
        print("  wrote", path)

    dump(out / "combined_summary.csv", summary,
         ["ablation","type","status","workers","pkt_floats","sizes",
          "n_ok","n_fail","mean_latency_us","cpu_percent",
          "cpu_wall_s","cpu_fmt","cpu_warn"])
    dump(out / "combined_latency.csv", lat_all,
         ["ablation","size_bytes","mean_us","median_us","p95_us","trimmed_us"])
    dump(out / "combined_scalability.csv", scal_all,
         ["ablation","num_workers","worker_id","latency_us","ok"])
    dump(out / "combined_cpu.csv", cpu_all,
         ["ablation","cpu_percent","cpu_wall_s","cpu_fmt"])

    # ---- console summary ----
    print()
    header = (f"{'ablation':<11} {'status':<14} {'ok':>3} {'fail':>5} "
              f"{'mean_lat_us':>12} {'cpu_pct':>20} {'wall_s':>8} "
              f"{'fmt':>7} {'warn':>12}")
    print(header)
    print("-" * len(header))
    for r in summary:
        print(f"{r['ablation']:<11} "
              f"{r['status']:<14} "
              f"{r['n_ok']:>3} "
              f"{r['n_fail']:>5} "
              f"{str(r['mean_latency_us']):>12} "
              f"{str(r['cpu_percent']):>20} "
              f"{str(r['cpu_wall_s']):>8} "
              f"{r['cpu_fmt']:>7} "
              f"{r['cpu_warn']:>12}")

    noisy = [r for r in summary if r["cpu_warn"] == "short_window"]
    if noisy:
        print()
        print(f"note: {len(noisy)} CPU measurement(s) below "
              f"{SHORT_WINDOW_S:.1f} s window - numbers are noisy:")
        for r in noisy:
            print(f"  {r['ablation']:<11} cpu={r['cpu_percent']}% "
                  f"wall={r['cpu_wall_s']}s")


if __name__ == "__main__":
    main()