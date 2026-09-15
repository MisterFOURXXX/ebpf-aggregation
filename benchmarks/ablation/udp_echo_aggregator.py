#!/usr/bin/env python3
"""Pure UDP echo server - no aggregation, no worker tracking.
Used by the A4 ablation (no-aggregation baseline)."""
import os, socket, struct

PORT = int(os.environ.get("PORT", "9999"))
PKT_FLOATS = int(os.environ.get("PKT_FLOATS", "64"))

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", PORT))
print(f"UDP echo on port {PORT} PKT_FLOATS={PKT_FLOATS}", flush=True)

while True:
    try:
        data, peer = s.recvfrom(65535)
        # request: uint32 worker_id + PKT_FLOATS floats
        # reply:   echo the floats unchanged
        floats = struct.unpack_from(f"<{PKT_FLOATS}f", data, 4)
        s.sendto(struct.pack(f"<{PKT_FLOATS}f", *floats), peer)
    except Exception as e:
        print("echo error:", e, flush=True)