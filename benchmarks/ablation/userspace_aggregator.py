#!/usr/bin/env python3
"""
Grouped userspace aggregator.
Collects packets from N workers, sums them, and replies when all N have arrived.
Used for A2, A3, A5, A6 (with different N).
"""
import socket, struct, sys, signal, os

UDP_IP = "0.0.0.0"
UDP_PORT = int(os.environ.get("AGG_PORT", "9999"))
NUM_WORKERS = int(os.environ.get("NUM_WORKERS", "1"))
BUF_SIZE = 32 * 1024 * 1024

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, BUF_SIZE)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, BUF_SIZE)
sock.bind((UDP_IP, UDP_PORT))
print(f"[A-grouped] Port={UDP_PORT} expected_workers={NUM_WORKERS}")

storage = {}          # key -> {'sum': [..], 'mask': int, 'addr': ...}
count = 0

def stop(s, f):
    print(f"\n[A-grouped] Processed {count} packets")
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

expected_mask = (1 << NUM_WORKERS) - 1

while True:
    try:
        data, addr = sock.recvfrom(4096)
        count += 1
        if len(data) < 12:
            continue
        session_id, seq_num, worker_id, payload_count = struct.unpack("<IIHH", data[:12])
        if payload_count == 0 or len(data) < 12 + payload_count * 4:
            continue
        payload = struct.unpack(f"<{payload_count}f", data[12:12 + payload_count*4])

        key = (session_id, seq_num)
        if key not in storage:
            storage[key] = {'sum': [0.0]*payload_count, 'mask': 0, 'addr': addr}
        e = storage[key]
        for i, v in enumerate(payload):
            e['sum'][i] += v
        e['mask'] |= (1 << worker_id)

        # Reply when all workers have contributed
        if e['mask'] == expected_mask:
            reply = struct.pack("<IIHH", session_id, seq_num, 0, payload_count)
            reply += struct.pack(f"<{payload_count}f", *e['sum'])
            sock.sendto(reply, addr)
            del storage[key]
    except Exception:
        continue