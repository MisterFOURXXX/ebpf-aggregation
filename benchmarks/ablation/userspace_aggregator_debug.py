#!/usr/bin/env python3
import socket
import struct

UDP_IP = "0.0.0.0"
UDP_PORT = 9999

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))
print(f"Userspace aggregator running on port {UDP_PORT} (DEBUG MODE)")

storage = {}
EXPECTED_WORKERS = 8
packet_count = 0

while True:
    data, addr = sock.recvfrom(2048)
    packet_count += 1
    print(f"Received packet #{packet_count} from {addr}, size={len(data)}")
    
    if len(data) < 12:
        print(f"  Packet too small: {len(data)} bytes")
        continue
    
    session_id, seq_num, worker_id, payload_floats = struct.unpack("<IIHH", data[:12])
    print(f"  session_id={session_id}, seq={seq_num}, worker={worker_id}, payload_floats={payload_floats}")
    
    if payload_floats > 0 and len(data) >= 12 + payload_floats * 4:
        payload = struct.unpack(f"<{payload_floats}f", data[12:12+payload_floats*4])
        print(f"  First few payload values: {payload[:3]}")
    
    key = (session_id, seq_num)
    if key not in storage:
        storage[key] = {'sum': [0.0]*payload_floats, 'mask': 0}
    
    entry = storage[key]
    for i, v in enumerate(payload):
        entry['sum'][i] += v
    entry['mask'] |= (1 << worker_id)
    
    if entry['mask'] == (1 << EXPECTED_WORKERS) - 1:
        print(f"  All {EXPECTED_WORKERS} workers received for key {key}, sending reply")
        reply = struct.pack("<IIHH", session_id, seq_num, 0, payload_floats)
        reply += struct.pack(f"<{payload_floats}f", *entry['sum'])
        sock.sendto(reply, addr)
        del storage[key]
