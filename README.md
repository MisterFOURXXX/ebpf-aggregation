# eBPF Gradient Aggregation for Distributed Machine Learning  
*(P4 / SmartNIC offload is a documented future extension only)*

### 1. Introduction

Imagine large AI models are trained — like ChatGPT, but smaller — across 8 computers instead of 1. Every time the model learns something, all 8 computers must agree on what they learned before moving forward. They do this by sending their “learning updates” (called gradients) to each other and adding them up. This process is called AllReduce.

**The problem:** Sending and adding up these gradients takes a huge amount of time. In real training runs it can consume 30–60 percent of total training time. The computers spend more time talking to each other than actually learning.

**The usual solutions:**

**Option A:** Run a small program on each computer that receives gradients, adds them, and sends the result back. This is what NCCL, Gloo and Horovod do. It works, but every packet must travel from the network card into the operating-system kernel, then up to a user program, and back down again. That trip is expensive.

**Option B:** Buy special hardware called SmartNICs or programmable switches that can add gradients inside the network itself, without involving the computer’s CPU at all. This is what SwitchML and ALEPH do. It is very fast, but the hardware costs thousands of dollars per machine and is not available on ordinary cloud servers.

This project aims to obtain most of the benefit of Option B using only software that already ships with every Linux computer — specifically the technology called eBPF — and to determine under what conditions it actually helps. eBPF lets small programs run inside the Linux kernel without modifying the kernel itself. It has been part of Linux since 2014 and is used by Meta, Google, Netflix and Cloudflare for high-speed networking, security and observability. Because eBPF is built into every modern Linux kernel, it works on any cloud server; no special hardware is required.

The project builds a complete testbed that compares three ways of performing AllReduce gradient aggregation:

- a normal userspace program (the baseline, comparable to NCCL),
- an eBPF/XDP program running inside the kernel (the experimental treatment),
- a “do-nothing” echo server (a control that isolates the pure cost of aggregation).

It then measures, very carefully, how fast each one is, how much CPU it uses, and how it scales as more workers are added.

#### 1.1 Existing Solutions

Two families of solutions exist today.

**Userspace aggregation.** A daemon on each node receives partial gradients over UDP or RDMA, sums them, and broadcasts the result. Used by NCCL, Gloo and Horovod. The cost is one kernel-to-user transition per packet plus the daemon’s CPU cost.

**In-network aggregation.** Programmable switches and SmartNICs perform the reduction inside the network fabric. Used by SwitchML (NSDI 2021) and ALEPH (SIGCOMM 2023). The cost is specialised hardware that is not available on commodity cloud instances.

Each family is optimal for a different range of parameters. The gap between them — commodity software that behaves like specialised hardware — is the space this project explores.

#### 1.2 eBPF

eBPF (extended Berkeley Packet Filter) has been part of Linux since kernel 4.8 (2016). It lets small, sandboxed programs run inside the kernel at various hook points without modifying or recompiling the kernel.

For networking the most interesting hook is XDP (eXpress Data Path). An XDP program runs inside the network driver, before the kernel allocates any packet buffer and before the networking stack runs. This is the earliest possible point at which a packet can be inspected or modified.

Two facts make eBPF a good fit for the problem:

- It is already available everywhere. Any Linux server with kernel ≥ 5.15 supports it. No special hardware is needed; a cloud VM that costs a few dollars per month can run XDP programs.
- It can reply directly. An XDP program that returns `XDP_TX` sends the packet back out the same interface, completely bypassing the kernel network stack. That is the fast path.

The intuition is therefore: if a userspace aggregator costs roughly 40 µs per small packet because of kernel transitions, and an XDP program can skip two of those transitions, the cost may fall to 10–20 µs — a factor of 2–4× improvement obtained for free on any hardware.

### 2. Project Motivation

#### 2.1 Economic

Large AI models are trained on clusters of hundreds or thousands of GPUs. Every hour of cluster time costs real money. If communication occupies 30 percent of that time, reducing it by half saves 15 percent of the total cost. On a $10 million training run that is $1.5 million saved. This is why every major AI laboratory invests heavily in communication optimisation.

#### 2.2 Accessibility

Current in-network aggregation solutions (SwitchML, ALEPH) require specialised hardware. Consequently:

- only well-funded laboratories and large companies can use them,
- researchers at smaller universities cannot reproduce the results,
- cloud users cannot benefit because providers do not offer programmable switches as a standard option.

If eBPF can deliver even 60 percent of the benefit of specialised hardware on commodity servers, every university and every start-up with cloud credits can use it. That is a far larger impact than another 10 percent improvement on hardware that 99 percent of people cannot access.

#### 2.3 Scientific

We do not yet know where the crossover point lies. We know:

- userspace is slow for small messages (per-packet overhead dominates),
- userspace is acceptable for large messages (bandwidth dominates),
- specialised hardware is fastest in both regimes but costs the most.

We do not know:

- exactly where eBPF sits between userspace and hardware,
- whether eBPF’s advantage grows or shrinks with message size,
- whether the advantage depends on the number of concurrent workers,
- whether the answer differs on loopback versus a real network card.

This project begins to answer those questions with careful, reproducible measurements.

### 3. Foundations

#### 3.1 Data-parallel Training

Large neural networks are trained on datasets too large for a single machine. The standard technique is **data-parallel training**: the batch is split across *N* workers, each of which computes a gradient on its local slice. The workers must then synchronise before the next step — every worker must update its weights with the *same* gradient — otherwise the model diverges into *N* different models.

The synchronisation operation is **AllReduce**: the *N* gradient tensors are summed element-wise and the result is distributed to every worker.

#### 3.2 AllReduce Bottleneck

For a model with *P* parameters and *N* workers a ring AllReduce exchanges approximately

```
2 × P × (N − 1) / N   bytes per training step.
```

At scale this volume is enormous. Two consequences follow:

1. **Communication dominates.** For transformer models with tens of billions of parameters, AllReduce occupies 30 percent to 60 percent of wall-clock time.
2. **It scales with the model, not with useful work.** As models grow, the communication fraction grows as well. Communication optimisation is therefore a first-order problem in ML systems.

#### 3.3 The Linux Network Stack

When a packet arrives at a Linux host the following steps occur (simplified):

```
1. The NIC receives the packet.
2. The NIC driver allocates an sk_buff (socket buffer).
3. The kernel parses the packet headers (L2, L3, L4).
4. The kernel looks up the socket that should receive the packet.
5. The packet is enqueued on that socket’s receive queue.
6. The application calls recv() and the kernel copies the data into userspace.
7. The application processes the packet.
8. The application calls send() and the kernel copies the response into a kernel buffer.
9. The kernel transmits the response through the NIC.
```

Every step is a source of latency. The two most expensive transitions are:

- **Step 2** – `sk_buff` allocation and initialisation (roughly 100 ns),
- **Step 6** – user-kernel context switch (roughly 1 µs).

For a userspace AllReduce daemon that handles small packets these transitions dominate.

#### 3.4 Kernel Bypass

Kernel bypass moves network processing out of the ordinary kernel stack. Examples include:

- **DPDK** – userspace poll-mode drivers that bypass the kernel entirely,
- **RDMA** – hardware support for direct memory access to a remote host,
- **eBPF/XDP** – programmable programs that run inside the kernel earlier than `sk_buff` allocation.

Each technique trades something for speed: DPDK requires dedicated CPU cores and a re-implemented network stack; RDMA requires specialised hardware; eBPF requires only a modern Linux kernel.

The eBPF choice in this project follows from the portability requirement: **run on any commodity Linux server without specialised hardware or dedicated cores.**

#### 3.5 eBPF Virtual Machine

eBPF is a register-based virtual machine embedded in the Linux kernel. Programs are written in a restricted C dialect, compiled by clang into eBPF bytecode, then verified by the kernel’s BPF verifier before being loaded. The verifier enforces two properties:

1. **Safety.** The program cannot access memory it does not own; every pointer dereference must be preceded by a bounds check.
2. **Termination.** The program must not loop forever; every loop must have a compile-time-boundable limit.

These constraints shape the whole design of an eBPF program: there is no `malloc`, no dynamic memory and no unbounded loop. Everything is fixed-size and pre-allocated.

#### 3.6 Hook Points

eBPF programs attach at **hook points**. The most important ones for networking are:

| Hook              | Location                        | Latency   | Replaces                  |
|-------------------|---------------------------------|-----------|---------------------------|
| XDP               | In the driver, before sk_buff   | Lowest    | NIC → driver → stack      |
| TC (cls_bpf)      | In the network stack, after sk_buff | Medium | Part of the stack         |
| Socket filter     | On socket receive               | Highest   | Nothing                   |
| kprobe / tracepoint | On kernel events              | Very high | Nothing                   |

**XDP is the earliest hook point.** A program attached here runs before the kernel even allocates a packet buffer. It can:

- inspect the raw bytes,
- modify them in place,
- return `XDP_DROP` (drop the packet),
- return `XDP_PASS` (let the kernel process it),
- return `XDP_TX` (retransmit on the same interface),
- return `XDP_REDIRECT` (send to another interface or an AF_XDP socket).

The design of this project uses `XDP_TX` for the fast path and `XDP_PASS` for the control. This is the earliest point at which the two behaviours can be distinguished.

#### 3.7 BPF Maps

BPF programs cannot use heap memory. Instead they use **BPF maps** — key-value stores shared between kernel and userspace. The map types most relevant to this project are:

- `BPF_MAP_TYPE_HASH` – one entry per key, shared across CPUs (needs locking),
- `BPF_MAP_TYPE_PERCPU_HASH` – one copy of the map per CPU, lock-free but requires a reduction step to read,
- `BPF_MAP_TYPE_LRU_HASH` – hash with LRU eviction.

The project uses `BPF_MAP_TYPE_PERCPU_HASH` to eliminate lock contention. Each CPU accumulates into its own copy; when the aggregator needs the total it sums across CPUs. This is the standard technique for high-throughput counting in eBPF.

#### 3.8 UDP Transport

Userspace AllReduce implementations (NCCL, Gloo, Horovod) use UDP, not TCP, for four reasons:

1. **Datagram semantics.** Each gradient slice is independent; there is no stream state to maintain.
2. **No head-of-line blocking.** A lost packet in one AllReduce round does not delay the next.
3. **Lower per-packet overhead.** TCP’s three-way handshake, ACKs and window management are unnecessary for a fixed request-reply protocol.
4. **Multicast capability.** UDP supports one-to-many, useful for the broadcast phase of AllReduce.

The project uses UDP for the same reasons. The wire protocol is not designed to tolerate packet loss because loopback is lossless. A production deployment would add sequence numbers and retransmission.

#### 3.9 Loopback

Loopback (`lo`) is a virtual network interface provided by the kernel for internal communication. Traffic sent to `127.0.0.1` never touches a physical NIC; the kernel routes it directly from the sender’s socket to the receiver’s socket.

Loopback has three properties relevant to the experiment:

1. **Zero loss.** No retransmissions are needed.
2. **Deterministic latency.** Physical NICs introduce interrupt coalescing, DMA setup and NIC-specific jitter; loopback does not.
3. **Minimal stack involvement.** No L2 framing, no ARP, no NIC driver.

The consequence is that loopback *understates* the cost of userspace aggregation. On a real NIC the userspace path would also pay for NAPI polling, DMA and interrupt handling — costs that the XDP path avoids. The project’s design acknowledges this bias explicitly.

#### 3.10 The Two-Port Model

The aggregator binds to `0.0.0.0:9999`. Clients send to `127.0.0.1:9999`. The kernel delivers each datagram to the aggregator’s receive queue. The aggregator replies by sending to the source address obtained from `recvfrom`.

This is a **symmetric request-reply protocol**: the client maintains no connection and the aggregator maintains no per-client state. The model matches the way a real AllReduce aggregator would be deployed as a daemon.

#### 3.11 The SwitchML Lineage

SwitchML (Sapio et al., NSDI 2021) demonstrated that programmable switches (Barefoot Tofino) can perform gradient aggregation inside the network. Workers send partial gradients to the switch; the switch sums them with its match-action pipeline; the result is broadcast back. Host CPU involvement is eliminated entirely.

SwitchML’s key insight is that **gradient aggregation is an associative reduction** and that associative reductions can be performed at any point on the network path. The remaining question is where to place the reduction for the best cost-benefit trade-off.

#### 3.12 The ALEPH Lineage

ALEPH (Li et al., SIGCOMM 2023) extended the SwitchML idea from switches to **commodity NICs that support eBPF**. Instead of requiring a Tofino switch, ALEPH attaches an eBPF program at the XDP hook on each worker node. The worker aggregates locally in the kernel and forwards the partially aggregated results to a coordinator.

ALEPH demonstrated that eBPF-based aggregation achieves a 20–31 percent reduction in training time and an 88 percent improvement in bandwidth relative to state-of-the-art frameworks. It is the direct predecessor of the present project.

#### 3.13 The Portability Gap

Both SwitchML and ALEPH require specialised configurations:

- SwitchML needs a programmable switch that costs thousands of dollars and is unavailable on cloud instances.
- ALEPH needs a NIC that supports XDP with `XDP_TX` to a remote host; such NICs exist on some servers but not on all.

This project asks a **narrower and more portable** question: **how much of the ALEPH benefit survives when the aggregator is a single host and the data path is loopback?** The answer tells a system designer whether eBPF aggregation is worth deploying on the commodity hardware already available, independently of whether ALEPH-grade NICs are present.

#### 3.14 Where the Project Sits

```
                Hardware                              Software
                ────────                              ────────
    High        │  SwitchML (Tofino switch)          │  (no software
    performance │  ALEPH (SmartNIC + XDP)            │   equivalent)
                │                                     │
                │  ─────────────────────────────────  │
                │                                     │
                │  This project (XDP on loopback)    │  Userspace
    Commodity   │                                     │  aggregator
    hardware    │                                     │  (NCCL, Gloo)
                │                                     │
```

The project occupies the middle-right cell: eBPF on commodity hardware, compared with a userspace baseline.

#### 3.15 One-Factor-at-a-Time

A controlled experiment varies **exactly one factor** at a time while holding everything else constant. This is the standard methodology of systems research and the foundation of the ablation study.

The eleven configurations are organised so that each group varies a single factor:

- A1–A4 vary execution context (workers and packet size fixed),
- A5-pkt16/32/64 vary packet size (context and workers fixed),
- A6-w1/w2/w4/w8 vary worker count (context and packet size fixed).

If several factors changed simultaneously the effect of any single factor would be confounded and causal inference would be impossible.

#### 3.16 Controls

Every experiment needs a **control** — a condition in which the factor of interest is absent. The project’s two controls are:

- `xdp_pass` — isolates the cost of attaching an XDP program,
- `udp_echo` — isolates the pure cost of aggregation.

Without controls a two-way comparison (userspace versus XDP) cannot distinguish which of several possible mechanisms explains an observed difference.

#### 3.17 The Trimmed Mean

Latency distributions on a shared machine have **heavy tails**: a small fraction of measurements are dramatically larger than the median because of scheduler pauses, interrupts or garbage collection. The standard tools are:

- **Mean** — sensitive to outliers,
- **Median** — robust but ignores distribution shape,
- **Trimmed mean** — discards the top and bottom 10 percent and averages the middle 80 percent.

The trimmed mean is the conventional choice in systems benchmarking because it supplies a stable central estimate while still using most of the data. The project reports all four statistics (mean, median, p95, trimmed mean) so that a reader can judge for herself.

### 4. Design Approach

#### 4.1 The Wire Protocol

The protocol is the contract between clients and aggregators. It must be small enough to be implemented identically in three languages (Python, C, BPF) yet expressive enough to support the ablation study.

**Protocol Layout**

```
Request:
  [0..3]    session_id      uint32      identifies the AllReduce session
  [4..7]    seq_num         uint32      packet sequence within the session
  [8..9]    worker_id       uint16      sender index (0..N-1)
  [10..11]  payload_count   uint16      number of float32 values
  [12..]    payload         float32[]   the gradient slice

Response:
  [0..3]    session_id      uint32      echoed
  [4..7]    seq_num         uint32      echoed
  [8..9]    worker_id       uint16      always 0 (marks the packet as a reply)
  [10..11]  payload_count   uint16      echoed
  [12..]    payload         float32[]   element-wise sum over workers
```

**Workflow — sending side**

```
+--------------------------------+
|  1. Caller supplies            |
|     - float32 array            |
|     - count N                  |
|     - worker_id                |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  2. chunker::split_tensor      |  Splits the full tensor into
|     into packets of max        |  MAX_INTS_PER_PKT-sized chunks
|     PKT_FLOATS floats each     |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  3. pack_chunk writes          |  Header (12 B) + payload
|     session_id, seq, worker,   |
|     count, then memcpy payload |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  4. udp_client::sendto         |  One UDP datagram per chunk
|     to (127.0.0.1, 9999)       |
+----------------+---------------+
                 |
                 v
                 waiting for reply...
```

**Workflow — receiving side**

```
+--------------------------------+
|  1. sock.recvfrom(1 MB)        |  Blocking read on 0.0.0.0:9999
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  2. Validate length ≥ 12 B     |  Drop anything shorter
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  3. Unpack header              |  struct.unpack_from("<IIHH", data, 0)
|     sid, seq, wid, pc          |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  4. Check len(data) ≥          |  Drop truncated packets
|     12 + pc*4                  |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  5. Aggregate (mode-dependent) |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  6. Build reply                |  struct.pack("<IIHH", sid, seq, 0, pc)
|     with wid=0                 |  + packed sum
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  7. sendto back to sender      |  Original address from recvfrom
+----------------+---------------+
```

Total header size is 12 bytes. Payload size is `4 × payload_count` bytes. The header carries exactly the information needed to distinguish sessions, identify the sender and validate length. Anything larger would inflate the packet and confound the latency measurement.

The protocol is intentionally small enough to be implemented identically in Python (userspace aggregator), C (XDP program) and C++ (benchmark clients). Any latency difference between the userspace and XDP paths must therefore be attributable to *where* the code runs, not to *what* it does.

#### 4.2 Design and Implementation Variants

Four variants implement the same wire protocol so that any performance difference is attributable solely to execution location:

| Variant    | Language | Where it runs                          | Purpose                                      |
|------------|----------|----------------------------------------|----------------------------------------------|
| userspace  | Python   | Ordinary user process, UDP port 9999   | Baseline (comparable to NCCL)                |
| ebpf_xdp   | C + BPF  | Inside the Linux kernel, XDP hook      | Experimental treatment                       |
| xdp_pass   | C + BPF  | Inside the kernel, but returns XDP_PASS| Control that isolates XDP attachment cost    |
| udp_echo   | Python   | User process, no aggregation           | Control that isolates the cost of aggregation|

#### 4.2.1. `userspace` — the baseline

Python is not the fastest language, but it is the clearest. The baseline's purpose is to establish the *order of magnitude* of userspace aggregation, not to be the fastest possible userspace implementation. A faster baseline (C or Rust) would narrow the gap to eBPF, making the treatment look less impressive. A slower baseline would widen it, making the treatment look better than it is. Python sits in the middle: it is fast enough to be a credible baseline and slow enough that a GIL bottleneck is visible in the scalability results (which is itself an interesting finding). UDP is the standard transport for NCCL, Gloo, and Horovod. A TCP baseline would introduce connection setup and stream semantics that are not part of the aggregation operation. UDP is what production systems use. The baseline runs continuously during an ablation. It is started once, receives all client traffic, and is stopped once. This matches the deployment pattern of a real userspace aggregator daemon.

```
+--------------------------------+
|  Start: python3 userspace_     |
|  aggregator_silent.py          |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  1. Read env vars              |  NUM_WORKERS, PKT_FLOATS, GROUPED
|     bind("0.0.0.0", 9999)      |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  2. Print startup banner       |  "Aggregator on port 9999 ..."
+----------------+---------------+
                 |
                 v
        +--------+--------+
        |  Main loop      |  (blocking recvfrom)
        +--------+--------+
                 |
                 v
+--------------------------------+
|  3. recvfrom(1 MB)             |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  4. Parse header + payload     |
+----------------+---------------+
                 |
                 v
        +--------+--------+
        |  GROUPED?       |
        +----+--------+---+
             |        |
          no |        | yes
             v        v
   +-----------+   +-------------------+
   | Echo      |   | Accumulate into   |
   | payload   |   | per-(sid,seq)     |
   | as sum    |   | bucket            |
   +-----+-----+   +--------+----------+
         |                  |
         |                  v
         |       +---------------------+
         |       | mask == 2^N - 1 ?   |
         |       +----+-----------+----+
         |            |           |
         |         no |        yes|
         |            v           |
         |       keep waiting     v
         |                  +-------------------+
         |                  | Build reply with  |
         |                  | element-wise sum  |
         |                  | Send to ALL N     |
         |                  | worker addresses  |
         |                  +--------+----------+
         |                           |
         v                           v
   +--------------------------------------+
   |  sendto(client_addr)                 |
   +--------------------------------------+
```

#### 4.2.2. `ebpf_xdp` — the treatment

eBPF can attach at several points in the kernel. XDP is the earliest point: it runs inside the driver, before the kernel allocates a network buffer (`sk_buff`). TC runs later in the network stack, after the buffer has been allocated. XDP therefore removes two costly operations (sk_buff allocation and the driver-to-stack transition) that TC does not. The reply can either go back out the same interface (XDP_TX) or be handed to the kernel stack (XDP_PASS). XDP_TX skips the kernel stack entirely, which is the maximum-bypass path. This is the "kernel bypass" configuration the experiment is designed to measure. The compiled BPF object (`aggregator.bpf.o`) is shipped. The userspace loader (`ebpf/xdp_aggregator`) that opens the object, sets its rodata, and calls `bpf_xdp_attach` is not built. This is a deliberate scope decision: the loader is a two-day engineering task whose implementation depends on the specific eBPF API version of the target kernel. Shipping the compiled object is enough to demonstrate the design; the loader is documented as the first roadmap item.

```
+--------------------------------+
|  Start: sudo ./ebpf/xdp_       |  (requires CAP_BPF + CAP_NET_ADMIN)
|  aggregator NUM_WORKERS=1 ...  |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  1. bpf_object__open_file      |  Load aggregator.bpf.o from disk
|     ("aggregator.bpf.o")       |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  2. bpf_object__load           |  Verifier checks the program
|     (kernel verifier runs)     |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  3. Set rodata                |  NUM_WORKERS and PKT_FLOATS
|     (constants baked in)       |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  4. bpf_xdp_attach             |  Attach to `lo` interface
|     (ifindex = lo, XDP native) |
+----------------+---------------+
                 |
                 v
        +--------+---------+
        |  Kernel driver   |
        |  receives packet |
        +--------+---------+
                 |
                 v
+--------------------------------+
|  5. XDP program runs           |  Before sk_buff allocation!
|     (per-packet, in-driver)    |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  6. Parse header, sum floats   |  Uses per-CPU BPF hash map
|     into BPF_MAP_TYPE_         |  for lock-free aggregation
|     PERCPU_HASH                |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  7. mask == expected?          |  Check if all workers contributed
+----------------+---------------+
                 |
             yes |
                 v
+--------------------------------+
|  8. XDP_TX                     |  Reply directly from driver,
|     swap src/dst MAC + IP      |  no kernel stack involved
+----------------+---------------+
```

**Key difference:** steps 5–8 happen entirely inside the network driver. No `sk_buff`, no socket, no context switch to userspace. On a real NIC this can shave hundreds of nanoseconds. On loopback the gain is smaller because the driver path is already cheap.

#### 4.2.3. `xdp_pass` — the kernel control

Suppose you compare `ebpf_xdp` (fast) against `userspace` (slow) and find that `ebpf_xdp` is 3× faster. Is the speedup because of the kernel bypass (`XDP_TX`)? Or is it because the program runs in the driver before the network stack? You cannot answer that from a two-way comparison. You need a third data point: a program that attaches at the same hook but *does not bypass the stack*. That is `xdp_pass`. The difference between `xdp_pass` and `ebpf_xdp` measures the pure benefit of `XDP_TX` over `XDP_PASS`. The difference between `xdp_pass` and `userspace` measures the pure cost of running a BPF program at the XDP hook (attachment overhead, verifier cost, map lookups) versus doing the same work in userspace. Without this control, the experiment would conflate two different effects.

```
+--------------------------------+
|  1-4. Same as ebpf_xdp         |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  5. XDP program runs           |  Parses, sums, updates map
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  6. Return XDP_PASS            |  Kernel allocates sk_buff,
|                                |  runs network stack, and the
|                                |  reply travels the normal
|                                |  socket path
+----------------+---------------+
```

This variant exists because it isolates the *attachment cost* of XDP (program runs, verifier overhead, map lookups) from the *bypass benefit* of `XDP_TX`. Comparing `xdp_pass` against `userspace` shows how much XDP itself costs. Comparing `ebpf_xdp` against `xdp_pass` shows how much `XDP_TX` saves.

#### 4.2.4. `udp_echo` — the aggregation control

The userspace aggregator does two things: it receives and sends network traffic, and it performs element-wise summation. The baseline measures the combined cost of both. To know how much of that cost is due to *aggregation*, you need a variant that does the network part but skips the summation. `udp_echo` does exactly that: it receives a packet, rewrites `worker_id = 0` (so the reply is accepted), and sends the packet back unchanged. The difference between `userspace` and `udp_echo` is the pure CPU cost of summation. This control produces one of the most interesting findings in the project: `udp_echo` uses *more* CPU than the userspace aggregator, even though it does less work per packet. The reason is that echo replies to every packet immediately, doubling the syscall rate. This is a good example of how a control experiment can reveal a non-obvious fact. A minimal aggregator that does no aggregation at all. It echoes back the request payload unchanged.

```
+--------------------------------+
|  1. Bind to 9999               |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  2. recvfrom                   |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  3. Rewrite worker_id to 0     |  So the client accepts it
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  4. sendto back                |  Payload unchanged
+----------------+---------------+
```

This variant exists because it isolates the *cost of the aggregation itself* from the cost of being a network service. `userspace` minus `udp_echo` = the pure addition cost. `udp_echo` alone = the network round-trip floor.


### 5. Evaluation (Host Measurements)

#### 5.1 Experiment Results

**Experiment 1 – Simple AllReduce**

```
AllReduce succeeded. First result: 1
```

The correctness check passes. All workers receive the sum of their inputs. The wire protocol, the aggregator and the client library are consistent with one another.

**Experiment 2 – Latency versus Payload Size**

| Payload | Mean (µs) | Median (µs) | p95 (µs) |
|---------|-----------|-------------|----------|
| 64 B    | 68        | 62          | 115      |
| 256 B   | 81        | 80          | 93       |
| 1 KB    | 189       | 165         | 344      |
| 4 KB    | 643       | 633         | 804      |
| 16 KB   | 2 217     | 2 253       | 2 646    |
| 64 KB   | 7 704     | 7 600       | 9 707    |
| 256 KB  | 33 252    | 33 226      | 45 992   |
| 1 MB    | 98 329    | 89 758      | 129 039  |

**Interpretation**

- **Small payloads (below 1 KB).** Latency is essentially flat (60–190 µs). This is the per-packet overhead floor: two UDP system calls, one context switch to the aggregator, one summation, two system calls back. Payload size does not dominate.
- **Large payloads (above 4 KB).** Latency grows linearly with payload size. The slope corresponds to roughly 10–15 GB/s of effective throughput (1 MB / 98 ms ≈ 10 GB/s). This is the memory-bandwidth ceiling of the loopback path, not a property of the aggregator’s algorithm.
- **p95 versus mean.** The p95 is consistently 1.3–1.5× the mean, indicating a moderate tail that is normal for loopback on a shared VM. The trimmed mean stays close to the mean, confirming that outliers do not dominate the average.

The flat regime below 1 KB is precisely where kernel bypass should help, because the cost is dominated by transitions that eBPF can eliminate. The linear regime above 4 KB is where kernel bypass cannot help, because the cost is dominated by copying bytes.

**Experiment 3 – Scalability**

| Workers | Mean latency (µs) | Scaling factor |
|---------|-------------------|----------------|
| 1       | 99                | 1.0×           |
| 2       | 117               | 1.18×          |
| 4       | 207               | 2.09×          |
| 8       | 434               | 4.38×          |

Going from 1 to 8 workers multiplies latency by 4.38×. Perfect linear scaling would be 8×; perfect parallel scaling would be 1×. The observed factor is consistent with Python’s Global Interpreter Lock serialising the aggregation loop: only one thread can hold the GIL at any moment, so the aggregator’s receive/sum/send cycle cannot overlap across workers. This is a userspace-specific bottleneck and the core argument for moving aggregation into eBPF, where each CPU can process packets independently.

**Experiment 4 – Aggregator CPU Utilisation**

```
Aggregator CPU time:  0.05 s
Wall time:            0.13 s
CPU Utilization:      37.78 percent (of 1 core)
Iterations OK:        50 / 50
```

| Variant                        | CPU (percent of one core) |
|--------------------------------|---------------------------|
| eBPF/XDP (ALEPH reference)     | 4.5                       |
| UDP/NCCL (gRPC reference)      | 72.0                      |
| Python aggregator (this work)  | 37.8                      |

The Python aggregator sits between the two reference points. It is more efficient than a naïve UDP echo (which replies to every packet immediately and therefore doubles the system-call rate) but far less efficient than eBPF/XDP, which runs in the kernel and bypasses the network stack. This places the project in the research space between commodity userspace and hardware offload.

The CPU measurement window is short (≈ 0.13–1.5 s). The `warn=short_window` flag appears for three configurations; the numbers are valid but noisy. A 2–3 second window would improve stability.

#### 5.2 Ablation Study Interpretation

**Coverage Summary**

| Ablation   | Status      | Latency | Scal | CPU  | Notes                          |
|------------|-------------|---------|------|------|--------------------------------|
| A1         | unavailable | MISS    | MISS | MISS | No eBPF loader                 |
| A2         | ok          | OK      | OK   | OK   | Userspace baseline             |
| A3         | unavailable | MISS    | MISS | MISS | No eBPF loader                 |
| A4         | ok          | OK      | OK   | OK   | UDP echo (no aggregation)      |
| A5-pkt16   | ok          | OK      | OK   | OK   | Packet size = 16 floats        |
| A5-pkt32   | ok          | OK      | OK   | OK   | Packet size = 32 floats        |
| A5-pkt64   | ok          | OK      | OK   | OK   | Packet size = 64 floats        |
| A6-w1      | ok          | OK      | OK   | OK   | 1 worker (grouped mode)        |
| A6-w2      | ok          | SKIP    | OK   | SKIP | 2 workers (multi-worker skip)  |
| A6-w4      | ok          | SKIP    | OK   | SKIP | 4 workers (multi-worker skip)  |
| A6-w8      | ok          | SKIP    | OK   | SKIP | 8 workers (multi-worker skip)  |

**What each group tells us**

**A1–A4 (execution context).**  
Only A2 (userspace) and A4 (echo) are measurable. A4 uses *more* CPU (59.5 percent) than A2 (36.5 percent) even though it performs less work per packet. The reason is that the echo server replies immediately to every packet and therefore doubles the system-call rate. Less work per packet does not always imply less CPU.

**A5 (packet-size sweep).**  
A5-pkt16 uses 36.9 percent CPU, A5-pkt32 uses 36.1 percent, A5-pkt64 uses 58.3 percent. Smaller packets cost less CPU because the aggregator spends less time copying data. Packet size has only a modest effect on latency (all means lie roughly between 9 900 µs and 15 000 µs), suggesting that on loopback the dominant cost is system-call overhead rather than payload copying.

**A6 (worker-count sweep).**  
A6-w1 has full data. A6-w2/w4/w8 correctly skip the single-client latency and CPU measurements: in grouped mode with *N* > 1 the aggregator waits for *N* packets before replying, so a single client never triggers a reply.

**Why A1 and A3 are unavailable.**  
The repository ships the compiled BPF object (`ebpf/aggregator.bpf.o`) but not the userspace loader that opens the object, sets its read-only data and calls `bpf_xdp_attach`. Writing that loader is a two-day engineering task and is the first item on the roadmap. Reporting the configurations as “unavailable” rather than inventing numbers is the scientifically honest choice.

**Per-config ablation study workflow**

```
+--------------------------------+
|  Input: NAME TYPE WORKERS      |
|         PKT_FLOATS SIZES...    |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  1. mkdir results/ablation/$N  |
|     Truncate aggregator.log,   |
|     latency_results.csv,       |
|     scalability_results.csv,   |
|     cpu_results.txt            |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  2. free_port                  |
|     - pkill aggregator         |
|     - fuser -k 9999/udp        |
|     - lsof -t kill any binder  |
|     - wait_port_free (30 s)    |
+----------------+---------------+
                 |
                 v
        +--------+--------+
        |  TYPE?          |
        +--+---+---+---+--+
           |   |   |   |
   ebpf_xdp xdp_pass userspace userspace_grouped
           |   |   |   |
           v   v   v   v
        (see section 2 for each)
                 |
                 v
+--------------------------------+
|  3. Wait until ss -lun shows   |  Real readiness check by socket
|     :9999 is bound (30 s max)  |  state, not by process liveness
+----------------+---------------+
                 |
                 v
        +--------+--------+
        |  MULTI=WORKERS>1|
        +--+----------+---+
          no          yes
           |            |
           v            v
+--------------+  +----------------------+
|  4a. Run     |  |  4b. Skip latency    |
|      latency |  |      (single-client  |
|      benchmark|  |      benchmark can't |
|              |  |      trigger group)  |
+------+-------+  +----------+-----------+
       |                     |
       +--------+------------+
                |
                v
+--------------------------------+
|  5. Run scalability benchmark  |  Always runs, regardless of MULTI
+----------------+---------------+
                 |
                 v
        +--------+--------+
        |  MULTI?         |
        +--+----------+---+
          no          yes
           |            |
           v            v
+--------------+  +----------------------+
|  6a. Run CPU |  |  6b. Skip CPU        |
|      benchmark| |      (same reason)   |
+------+-------+  +----------+-----------+
       |                     |
       +--------+------------+
                |
                v
+--------------------------------+
|  7. Write metadata.txt         |  status, type, workers, pkt_floats,
|                                |  sizes, pid, skip markers
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  8. Kill aggregator            |  TERM, wait 1 s, KILL
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  9. free_port and verify       |
+----------------+---------------+
```

**Master ablation study workflow**

```
+--------------------------------+
|  For NAME in A1 A2 A3 A4       |
|              A5-pkt16          |
|              A5-pkt32          |
|              A5-pkt64          |
|              A6-w1 A6-w2       |
|              A6-w4 A6-w8:      |
|    run_one_ablation.sh $NAME   |
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  combine_results.py            |  Reads all 11 directories,
|                                |  writes 4 merged CSVs
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  plot_ablation.py              |  Reads merged CSVs,
|                                |  writes 6-panel figure
+----------------+---------------+
                 |
                 v
+--------------------------------+
|  Print paths and file listing  |
+--------------------------------+
```

### 6. Key Findings

1. **Latency scales linearly with payload size** above 4 KB, with a slope of approximately 10 GB/s — a bandwidth-limited regime.
2. **Latency is flat below 1 KB** (≈ 60–190 µs) — an overhead-limited regime, exactly where kernel bypass can help.
3. **Scalability is sub-linear** (4.38× at 8 workers), consistent with GIL serialisation. This is a userspace-specific bottleneck and the central argument for eBPF.

**CPU positioning.**  
The Python aggregator consumes 37.8 percent of one core, lying between the ALEPH reference (4.5 percent) and the UDP/NCCL reference (72 percent). The project therefore occupies the research space between commodity userspace and hardware offload.

**Limitations (each with a concrete roadmap item)**

- A1 and A3 unavailable (no eBPF loader) → write the loader.
- All measurements on loopback (biases against eBPF) → repeat on 25 GbE.
- CPU is single-process (no per-CPU accounting) → add per-CPU instrumentation.
- Multi-worker CPU skipped by design → redesign the multi-worker CPU benchmark.
- Short measurement windows on three configurations → lengthen the window to 2–3 s.

### 7. Summary

The formal research question is:

> Given a fixed AllReduce protocol and a fixed set of payload sizes, what is the latency and CPU cost of aggregating *N* concurrent workers in userspace versus in an XDP program, and how does that ratio depend on payload size, packet size and worker count?

The present results answer the question partially:

- **Userspace cost** – fully characterised (68 µs at 64 B to 98 ms at 1 MB; CPU 36.8–59.5 percent).
- **Payload-size dependence** – fully characterised (linear above 4 KB, flat below 1 KB).
- **Packet-size dependence** – partially characterised (small effect on latency, moderate effect on CPU).
- **Worker-count dependence** – partially characterised (sub-linear scaling, consistent with the GIL).

### 8. Suggested Next Steps

1. Write the eBPF loader (`ebpf/xdp_aggregator`) so that A1 and A3 become runnable (approximately two days of work).
2. Increase the CPU-benchmark window to 2–3 seconds to eliminate the `short_window` warning.
3. Repeat the measurements on a physical NIC (25 GbE or higher) to quantify the loopback bias.
4. Extend the ablation with a DPDK aggregator and a multiprocessing userspace variant, placing eBPF on the full spectrum between kernel and full userspace bypass.
5. Formalise a cost model that expresses aggregator latency as a function of payload size, packet size, worker count and per-packet overhead.
6. (Future) Implement the P4 SmartNIC offload path once suitable hardware is available; the current codebase already reserves the necessary placeholders.

---

### Get Start – Reproducibility (operational commands)

The scientific claims above rest exclusively on the host measurements. Docker and Kubernetes are packaging and orchestration artefacts; they are **not** part of the experimental data path.

**Docker and Kubernetes Related to the Project**

Docker and Kubernetes serve **different purposes** in this project, and neither of them is required for the main ablation study. Understanding the distinction matters because a reader might assume they participate in the research measurements.

**What Docker is for in this project?**

Docker is used to build a **self-contained build environment**. The `Dockerfile` at the project root installs every build dependency (clang, libbpf, cmake, python3, etc.) inside an Ubuntu 22.04 image and then compiles the project inside that image.

Purpose:

1. **Portability of the build.** A reviewer on any Linux system can run `docker build -t ebpf-p4-agg .` and get a working set of binaries without installing anything on the host.
2. **Reproducibility of dependencies.** The exact versions of every tool are pinned by the base image and the `apt-get install` line.
3. **Integration test.** `scripts/test.sh docker` builds the image and runs `simple_allreduce` inside it, verifying that the build is reproducible and the binary works.

The ablation study runs on the host (or on a cloud VM) using the directly compiled binaries. This is deliberate: the ablation needs to run the aggregator as a persistent process on port 9999, and containerizing it would add a network namespace boundary that changes the latency characteristics. The measurements must be on the host for them to be meaningful.

**What Kubernetes is for in this project?**

Kubernetes is used to demonstrate the **cloud-native orchestration path**. The project includes a Kubernetes Operator written in Go that watches a custom resource called `GradientAggregation` and reconciles the cluster to match the declared state. The Kubernetes path is **not** used for the ablation study either. It is a research artefact that shows:

1. **The declarative deployment model.** The operator accepts a YAML specification and reconciles the cluster to match it.
2. **The bpfd integration path.** In a full deployment, the operator would call bpfd (a system daemon for loading eBPF programs) to load the aggregator on each node. In the current prototype, this is stubbed.
3. **Cloud-native testability.** The `scripts/test.sh k8s` subcommand creates a KIND cluster, deploys the operator, and verifies the operator reconciles.

This study is about execution context (userspace vs. kernel) and payload size (64 B to 1 MB), not about orchestration. The Kubernetes code exists to demonstrate the deployment path and to show that the same aggregation logic can be managed through Kubernetes CRDs.  


**Host workflow (recommended)**

```bash
cd ~/ebpf-aggregation
bash scripts/setup.sh          # once
bash scripts/build.sh
bash scripts/test.sh preflight # must print “13 passed, 0 failed”
bash scripts/test.sh smoke
bash scripts/run_experiments.sh
bash scripts/run_ablation.sh
bash scripts/validate.sh       # 11 passed, 0 failed
```

**Kubernetes fast pre-flight (≈ 3 min) before any long ablation**

```bash
bash scripts/k8s-run.sh clean
bash scripts/k8s-run.sh test   # must print “[TEST] PASSED”
```

Only after the test passes:

```bash
bash scripts/k8s-run.sh        # full pipeline (experiments + 11-config ablation + 6-panel report)
# or
bash scripts/k8s-run.sh exp
bash scripts/k8s-run.sh abl
```

After a successful Kubernetes run the six-panel ablation report appears at  
`k8s-results/ablation/ablation/ablation_report.png`  
and the three experiment plots (including the three-bar CPU comparison) appear under  
`k8s-results/plots/`.

---

All diagrams, tables, numerical results and scientific interpretation from the original document have been retained. The only material removed or relocated is the lengthy operational command listings that previously interrupted the research narrative; they now live in the short appendix above.