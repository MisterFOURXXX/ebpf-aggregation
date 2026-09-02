#!/usr/bin/env python3
import socket
import struct

UDP_IP = "0.0.0.0"
UDP_PORT = 9999
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))
print("Userspace aggregator running on port 9999 (CPU-intensive)")

storage = {}
EXPECTED_WORKERS = 8

while True:
    data, addr = sock.recvfrom(2048)
    if len(data) < 12:
        continue
    session_id, seq_num, worker_id, payload_floats = struct.unpack("<IIHH", data[:12])
    payload = struct.unpack(f"<{payload_floats}f", data[12:12+payload_floats*4])
    key = (session_id, seq_num)
    if key not in storage:
        storage[key] = {'sum': [0.0]*payload_floats, 'mask': 0}
    entry = storage[key]
    for i, v in enumerate(payload):
        entry['sum'][i] += v
    entry['mask'] |= (1 << worker_id)
    if entry['mask'] == (1 << EXPECTED_WORKERS) - 1:
        reply = struct.pack("<IIHH", session_id, seq_num, 0, payload_floats)
        reply += struct.pack(f"<{payload_floats}f", *entry['sum'])
        sock.sendto(reply, addr)
        del storage[key]