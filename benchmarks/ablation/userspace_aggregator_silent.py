#!/usr/bin/env python3
"""
Userspace UDP aggregator with grouped and ungrouped modes.

Env vars:
  AGG_PORT      UDP port                 default 9999
  NUM_WORKERS   group size               default 1
  PKT_FLOATS    float32 per packet       default 64
  GROUPED       0 = reply to each pkt    1 = wait for N pkts, then reply to all
  TYPE          userspace | userspace_grouped  (default userspace)

Wire format (must match C++ benchmarks):
  request:  uint32 session_id | uint32 seq | uint16 worker_id | uint16 count | count*float32
  reply:    uint32 session_id | uint32 seq | uint16 0         | uint16 count | count*float32
"""
import os, socket, struct, sys, signal

AGG_PORT    = int(os.environ.get("AGG_PORT", "9999"))
NUM_WORKERS = int(os.environ.get("NUM_WORKERS", "1"))
PKT_FLOATS  = int(os.environ.get("PKT_FLOATS", "64"))
TYPE        = os.environ.get("TYPE", "userspace")

# Infer grouped mode from TYPE if GROUPED is not set explicitly.
_default_grouped = "1" if TYPE == "userspace_grouped" else "0"
GROUPED = int(os.environ.get("GROUPED", _default_grouped))

MAX_FLOATS = max(PKT_FLOATS, 4096)   # tolerate larger incoming packets
BUF_SIZE   = 32 * 1024 * 1024

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, BUF_SIZE)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, BUF_SIZE)
sock.bind(("0.0.0.0", AGG_PORT))

print("Aggregator on port %d NUM_WORKERS=%d PKT_FLOATS=%d GROUPED=%s TYPE=%s"
      % (AGG_PORT, NUM_WORKERS, PKT_FLOATS, bool(GROUPED), TYPE))
sys.stdout.flush()

storage       = {}
packet_count  = 0
expected_mask = (1 << NUM_WORKERS) - 1


def stop(signum, frame):
    print("Processed %d packets" % packet_count)
    sys.stdout.flush()
    sys.exit(0)


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT,  stop)

while True:
    try:
        data, addr = sock.recvfrom(1 << 20)
        packet_count += 1
    except Exception:
        continue

    if len(data) < 12:
        continue

    sid, seq, wid, pc = struct.unpack_from("<IIHH", data, 0)
    if pc == 0 or pc > MAX_FLOATS:
        continue
    if len(data) < 12 + pc * 4:
        continue

    payload = struct.unpack_from("<%df" % pc, data, 12)

    # -- ungrouped: echo back immediately --
    if not GROUPED:
        reply = struct.pack("<IIHH", sid, seq, 0, pc) + \
                struct.pack("<%df" % pc, *payload)
        sock.sendto(reply, addr)
        continue

    # -- grouped: accumulate until all N workers have contributed --
    key = (sid, seq)
    if key not in storage:
        storage[key] = {"sum": [0.0] * pc, "mask": 0, "addrs": {}}
    e = storage[key]
    for i in range(pc):
        e["sum"][i] += payload[i]
    e["mask"] |= (1 << wid)
    e["addrs"][wid] = addr

    if e["mask"] == expected_mask:
        reply = struct.pack("<IIHH", sid, seq, 0, pc) + \
                struct.pack("<%df" % pc, *e["sum"])
        for waddr in e["addrs"].values():
            sock.sendto(reply, waddr)
        del storage[key]