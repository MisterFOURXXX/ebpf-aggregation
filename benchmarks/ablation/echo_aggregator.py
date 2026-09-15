#!/usr/bin/env python3
"""A4 - UDP echo aggregator. Returns the packet unchanged."""
import socket, sys, signal, os

UDP_IP   = "0.0.0.0"
UDP_PORT = int(os.environ.get("AGG_PORT", "9999"))
BUF_SIZE = 32 * 1024 * 1024

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, BUF_SIZE)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, BUF_SIZE)
sock.bind((UDP_IP, UDP_PORT))
print(f"A4 Echo aggregator on port {UDP_PORT}", flush=True)

count = 0


def stop(s, f):
    print(f"A4 processed {count} packets", flush=True)
    sys.exit(0)


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

while True:
    try:
        data, addr = sock.recvfrom(65536)
        count += 1
        if len(data) < 12:
            continue
        sock.sendto(data, addr)         # echo unchanged
    except Exception:
        continue