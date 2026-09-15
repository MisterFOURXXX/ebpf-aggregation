#!/usr/bin/env python3
"""
Grouped userspace aggregator.
Collects packets from N workers, sums them, replies to ALL workers.
Used for A2, A3, A5, A6 (with different N).
"""
import socket, struct, sys, signal, os

UDP_IP      = "0.0.0.0"
UDP_PORT    = int(os.environ.get("AGG_PORT", "9999"))
NUM_WORKERS = int(os.environ.get("NUM_WORKERS", "1"))
BUF_SIZE    = 32 * 1024 * 1024

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, BUF_SIZE)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, BUF_SIZE)
sock.bind((UDP_IP, UDP_PORT))
print("Grouped aggregator port=%d workers=%d" % (UDP_PORT, NUM_WORKERS))
sys.stdout.flush()

storage = {}
count = 0
expected_mask = (1 << NUM_WORKERS) - 1

def stop(s, f):
    print("Grouped aggregator processed %d packets" % count)
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
        sid, seq, wid, pc = struct.unpack("<IIHH", data[:12])
        if pc == 0 or len(data) < 12 + pc * 4:
            continue
        payload = struct.unpack("<%df" % pc, data[12:12 + pc * 4])

        key = (sid, seq)
        if key not in storage:
            storage[key] = {
                'sum': [0.0] * pc,
                'mask': 0,
                'workers': {},
            }
        e = storage[key]
        for i, v in enumerate(payload):
            e['sum'][i] += v
        e['mask'] |= (1 << wid)
        e['workers'][wid] = addr

        if e['mask'] == expected_mask:
            reply  = struct.pack("<IIHH", sid, seq, 0, pc)
            reply += struct.pack("<%df" % pc, *e['sum'])
            for _, waddr in e['workers'].items():
                sock.sendto(reply, waddr)
            del storage[key]
    except Exception:
        continue