#!/usr/bin/env python3
"""
A4 - Echo aggregator (no aggregation).
Echoes back each packet, representing pure UDP round-trip latency.
"""
import socket, struct, sys, signal, os

UDP_IP   = "0.0.0.0"
UDP_PORT = int(os.environ.get("AGG_PORT", "9999"))
BUF_SIZE = 32 * 1024 * 1024

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, BUF_SIZE)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, BUF_SIZE)
sock.bind((UDP_IP, UDP_PORT))
print("A4 Echo aggregator on port %d" % UDP_PORT)
sys.stdout.flush()

count = 0
def stop(s, f):
    print("A4 processed %d packets" % count)
    sys.stdout.flush()
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

while True:
    try:
        data, addr = sock.recvfrom(4096)
        count += 1
        if len(data) < 12:
            continue
        # Echo back unchanged
        sock.sendto(data, addr)
    except Exception:
        continue
