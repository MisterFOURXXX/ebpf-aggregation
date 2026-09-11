#!/usr/bin/env python3
import socket
import struct
import sys

UDP_IP = "0.0.0.0"
UDP_PORT = 9999

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))
print(f"Aggregator running on port {UDP_PORT}")

storage = {}
packet_count = 0

def main():
    global packet_count
    while True:
        try:
            data, addr = sock.recvfrom(2048)
            packet_count += 1
            if len(data) < 12:
                continue
            session_id, seq_num, worker_id, payload_floats = struct.unpack("<IIHH", data[:12])
            if payload_floats == 0 or len(data) < 12 + payload_floats * 4:
                continue
            payload = struct.unpack(f"<{payload_floats}f", data[12:12+payload_floats*4])
            key = (session_id, seq_num)
            if key not in storage:
                storage[key] = {'sum': [0.0]*payload_floats, 'mask': 0}
            entry = storage[key]
            for i, v in enumerate(payload):
                entry['sum'][i] += v
            entry['mask'] |= (1 << worker_id)
            if entry['mask'] == (1 << worker_id):
                reply = struct.pack("<IIHH", session_id, seq_num, 0, payload_floats)
                reply += struct.pack(f"<{payload_floats}f", *entry['sum'])
                sock.sendto(reply, addr)
                del storage[key]
        except KeyboardInterrupt:
            print(f"\nProcessed {packet_count} packets")
            sys.exit(0)
        except:
            continue

if __name__ == "__main__":
    main()
