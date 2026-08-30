#!/usr/bin/env python3
import socket
import struct

UDP_IP = "0.0.0.0"
UDP_PORT = 9999
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))
print("[Userspace Aggregator] Running on port 9999 (CPU-intensive)")

storage = {}

while True:
    data, addr = sock.recvfrom(2048)
    if len(data) < 12:
        continue
    session_id, seq_num, worker_id, payload_ints = struct.unpack("<IIHH", data[:12])
    payload = struct.unpack(f"<{payload_ints}i", data[12:12+payload_ints*4])

    key = (session_id, seq_num)
    if key not in storage:
        storage[key] = {'sum': [0] * payload_ints, 'mask': 0, 'expected': 8}

    entry = storage[key]
    for i, val in enumerate(payload):
        entry['sum'][i] += val
    entry['mask'] |= (1 << worker_id)

    if entry['mask'] == (1 << entry['expected']) - 1:
        reply = struct.pack("<IIHH", session_id, seq_num, 0, payload_ints)
        reply += struct.pack(f"<{payload_ints}i", *entry['sum'])
        sock.sendto(reply, addr)
        del storage[key]