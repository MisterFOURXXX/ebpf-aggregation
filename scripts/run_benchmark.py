#!/usr/bin/env python3
import subprocess
import sys

def run_cpu(ip, port, wid):
    cmd = ["./build/benchmarks/cpu_benchmark", ip, str(port), str(wid)]
    out = subprocess.check_output(cmd).decode()
    for line in out.split('\n'):
        if "CPU Utilization" in line:
            return float(line.split(':')[1].strip().rstrip('%'))
    return None

def run_latency(ip, port, wid):
    cmd = ["./build/benchmarks/latency_benchmark", ip, str(port), str(wid)]
    with open("latency_results.csv", "w") as f:
        f.write(subprocess.check_output(cmd).decode())

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: run_benchmark.py <ip> <port> <worker_id>")
        sys.exit(1)
    ip, port, wid = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    cpu = run_cpu(ip, port, wid)
    print(f"CPU usage: {cpu}%")
    run_latency(ip, port, wid)