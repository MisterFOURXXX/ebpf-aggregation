#!/bin/bash
# ============================================================
# test.sh - unified testing
#
#   usage:
#     bash scripts/test.sh native
#     bash scripts/test.sh docker
#     bash scripts/test.sh k8s
#     bash scripts/test.sh all
#     bash scripts/test.sh smoke
#     bash scripts/test.sh one <NAME>
#     bash scripts/test.sh preflight
#     bash scripts/test.sh quick
# ============================================================
set +m
cd "$(dirname "$0")/.."
ROOT=$(pwd)
LOG="$ROOT/benchmarks/results"
IMG=ebpf-p4-agg:latest
CLUSTER=ebpf-test
mkdir -p "$LOG"


# ============================================================
# run_native
# ============================================================
run_native() {
    echo "Native test suite"
    ./scripts/clean.sh >/dev/null 2>&1 || true
    ./scripts/build.sh >/dev/null 2>&1 || { echo "Build FAILED"; return 1; }
    mkdir -p "$LOG"

    echo "Unit tests"
    (cd "$ROOT/tests/build" && ctest 2>&1 | tail -3)

    pkill -f userspace_aggregator_silent.py 2>/dev/null || true
    sleep 1
    python3 benchmarks/ablation/userspace_aggregator_silent.py >/dev/null 2>&1 &
    AGG_PID=$!
    sleep 2
    if ! kill -0 $AGG_PID 2>/dev/null; then
        echo "Aggregator failed to start"
        return 1
    fi

    echo "Example"
    (cd "$ROOT/examples/build" && timeout 20 ./simple_allreduce 127.0.0.1 9999 0) \
        | tee "$LOG/example.txt"

    echo "Latency"
    (cd "$ROOT/benchmarks/build" && timeout 30 ./latency_benchmark 127.0.0.1 9999 0) \
        | tee "$LOG/latency_results.csv"

    echo "Scalability"
    (cd "$ROOT/benchmarks/build" && timeout 20 ./scalability_benchmark 127.0.0.1 9999 2) \
        | tee "$LOG/scalability_results.csv"

    echo "CPU"
    (cd "$ROOT/benchmarks/build" && timeout 15 ./cpu_benchmark 127.0.0.1 9999 0 $AGG_PID) \
        | tee "$LOG/cpu_results.txt"

    pkill -f userspace_aggregator_silent.py 2>/dev/null || true
    echo "Native tests done. Results in $LOG"
}


# ============================================================
# run_docker
# ============================================================
run_docker() {
    echo "Docker test"
    echo "Building image"
    if ! sudo docker build -t "$IMG" . ; then
        echo "Docker build FAILED"
        return 1
    fi
    echo "Image built: $IMG"

    echo "Running integration test"
    sudo docker run --rm --privileged --network host "$IMG" \
        bash -c "cd /app && \
                 pkill -f userspace_aggregator_silent.py 2>/dev/null; \
                 python3 benchmarks/ablation/userspace_aggregator_silent.py & \
                 sleep 2; \
                 cd examples/build && timeout 20 ./simple_allreduce 127.0.0.1 9999 0; \
                 pkill -f userspace_aggregator_silent.py"
    echo "Docker test done"
}


# ============================================================
# run_k8s
# ============================================================
# ============================================================
# run_k8s_experiments - run the 4 experiments + ablation as
# Kubernetes Jobs and copy results back to the host.
# ============================================================
run_k8s_experiments() {
    local CLUSTER=ebpf-p4
    local RESULTS_DIR="$ROOT/k8s-results"
    rm -rf "$RESULTS_DIR"
    mkdir -p "$RESULTS_DIR"

    printf 'Cleaning leftover clusters\n'
    kind delete cluster --name "$CLUSTER"   2>/dev/null || true
    kind delete cluster --name ebpf-test   2>/dev/null || true

    printf 'Rebuilding ebpf-p4-agg image\n'
    sudo docker build -t ebpf-p4-agg:latest . || return 1

    printf 'Rebuilding operator image\n'
    ( cd "$ROOT/operator" && make docker-build IMG=ebpf-p4-operator:latest ) || return 1

    printf 'Creating KIND cluster %s\n' "$CLUSTER"
    kind create cluster --name "$CLUSTER" --wait 90s || return 1
    kind export kubeconfig --name "$CLUSTER"

    printf 'Loading images into KIND\n'
    kind load docker-image ebpf-p4-agg:latest      --name "$CLUSTER" || return 1
    kind load docker-image ebpf-p4-operator:latest --name "$CLUSTER" || return 1

    printf 'Deploying operator\n'
    kubectl apply -f "$ROOT/operator/config/crd/mlaccel.io_gradientaggregations.yaml"
    kubectl apply -f "$ROOT/deploy/operator.yaml"
    kubectl apply -f "$ROOT/operator/config/sample/gradientaggregation.yaml"

    printf 'Waiting for operator pod\n'
    kubectl wait --for=condition=Ready pod \
        -l app=ebpf-p4-operator -n mlaccel-system --timeout=120s || true

    printf 'Running experiments Job\n'
    kubectl apply -f "$ROOT/deploy/experiment-job.yaml"
    kubectl wait --for=condition=complete job/ebpf-p4-experiments --timeout=600s || true
    kubectl logs job/ebpf-p4-experiments > "$RESULTS_DIR/experiments.log"

    printf 'Copying experiment results\n'
    local POD
    POD=$(kubectl get pods -l job-name=ebpf-p4-experiments \
          -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$POD" ]; then
        kubectl cp "default/${POD}:/results" "$RESULTS_DIR/experiments/"
    fi

    printf 'Running ablation Job\n'
    kubectl apply -f "$ROOT/deploy/ablation-job.yaml"
    kubectl wait --for=condition=complete job/ebpf-p4-ablation --timeout=1800s || true
    kubectl logs job/ebpf-p4-ablation > "$RESULTS_DIR/ablation.log"

    printf 'Copying ablation results\n'
    POD=$(kubectl get pods -l job-name=ebpf-p4-ablation \
          -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$POD" ]; then
        kubectl cp "default/${POD}:/results" "$RESULTS_DIR/ablation/"
    fi

    printf 'Results on host:\n'
    ls -la "$RESULTS_DIR"
}

# ============================================================
# run_smoke
# ============================================================
run_smoke() {
    printf '[smoke] freeing port 9999\n'
    sudo pkill -KILL -f '[u]serspace_aggregator'  >/dev/null 2>&1 || true
    sudo pkill -KILL -f '[e]cho_aggregator'       >/dev/null 2>&1 || true
    command -v fuser >/dev/null 2>&1 && sudo fuser -k -KILL 9999/udp >/dev/null 2>&1 || true
    command -v lsof  >/dev/null 2>&1 && \
        sudo lsof -t -iUDP:9999 2>/dev/null | xargs -r sudo kill -9 2>/dev/null || true
    sleep 1
    if ss -lun 2>/dev/null | grep -q ':9999'; then
        printf '[smoke] FAILED - port 9999 still busy\n'
        return 1
    fi

    printf '[smoke] starting aggregator\n'
    NUM_WORKERS=1 python3 benchmarks/ablation/userspace_aggregator_silent.py \
        > /tmp/smoke_agg.log 2>&1 &
    AGG=$!
    disown

    for i in $(seq 1 20); do
        ss -lun 2>/dev/null | grep -q ':9999' && break
        sleep 0.5
    done
    if ! ss -lun 2>/dev/null | grep -q ':9999'; then
        printf '[smoke] FAILED - aggregator did not bind within 10s\n'
        printf -- '---- aggregator.log ----\n'
        sed 's/^/  /' /tmp/smoke_agg.log
        kill -KILL "$AGG" 2>/dev/null || true
        return 1
    fi

    printf '[smoke] step 1/2 - raw handshake\n'
    if ! python3 - <<'PY'
import socket, struct, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2.0)
pc = 16
hdr  = struct.pack("<IIHH", 0x1234, 1, 0, pc)
body = struct.pack(f"<{pc}f", *([1.0]*pc))
try:
    s.sendto(hdr + body, ("127.0.0.1", 9999))
    reply, _ = s.recvfrom(65536)
    sid, seq, wid, rpc = struct.unpack_from("<IIHH", reply, 0)
    vals = struct.unpack_from(f"<{rpc}f", reply, 12)
    print(f"[smoke] handshake OK: {len(reply)}B, first float={vals[0]}")
    sys.exit(0)
except socket.timeout:
    print("[smoke] handshake FAILED - no reply within 2s")
    sys.exit(1)
PY
    then
        printf -- '---- aggregator.log ----\n'
        sed 's/^/  /' /tmp/smoke_agg.log
        kill -KILL "$AGG" 2>/dev/null || true
        return 1
    fi

    printf '[smoke] step 2/2 - latency benchmark (15s timeout)\n'
    OUT=/tmp/smoke_latency.csv
    ( cd benchmarks/build && timeout 15 ./latency_benchmark 127.0.0.1 9999 0 ) \
        > "$OUT" 2>/dev/null || true

    kill -KILL "$AGG" 2>/dev/null || true

    ROWS=$(grep -cE '^[0-9]' "$OUT" 2>/dev/null) || ROWS=0
    FAILS=$(grep -c 'FAIL' "$OUT" 2>/dev/null)   || FAILS=0
    printf '[smoke] rows=%s fails=%s\n' "$ROWS" "$FAILS"

    if [ "$ROWS" -ge 8 ] && [ "$FAILS" -eq 0 ]; then
        printf '[smoke] ALL PASSED\n'
        cat "$OUT"
        return 0
    fi

    printf '[smoke] FAILED\n'
    cat "$OUT"
    return 1
}


# ============================================================
# run_one NAME
# ============================================================
run_one() {
    local NAME=$1
    local OUT="$ROOT/benchmarks/results/ablation"

    if [ -z "$NAME" ]; then
        printf 'Usage: %s one <A1|A2|A3|A4|A5-pkt16|A5-pkt32|A5-pkt64|A6-w1|A6-w2|A6-w4|A6-w8>\n' "$0"
        return 1
    fi

    local TYPE WORKERS PKT SIZES
    case "$NAME" in
        A1)        TYPE=ebpf_xdp;          WORKERS=1; PKT=64; SIZES="64 256 1024 4096 16384 65536" ;;
        A2)        TYPE=userspace;         WORKERS=1; PKT=64; SIZES="64 256 1024 4096 16384 65536" ;;
        A3)        TYPE=xdp_pass;          WORKERS=1; PKT=64; SIZES="64 256 1024 4096 16384 65536" ;;
        A4)        TYPE=userspace;         WORKERS=1; PKT=64; SIZES="64 256 1024 4096 16384 65536" ;;
        A5-pkt16)  TYPE=userspace;         WORKERS=1; PKT=16; SIZES="64 256 1024 4096 16384 65536" ;;
        A5-pkt32)  TYPE=userspace;         WORKERS=1; PKT=32; SIZES="64 256 1024 4096 16384 65536" ;;
        A5-pkt64)  TYPE=userspace;         WORKERS=1; PKT=64; SIZES="64 256 1024 4096 16384 65536" ;;
        A6-w1)     TYPE=userspace_grouped; WORKERS=1; PKT=64; SIZES="256" ;;
        A6-w2)     TYPE=userspace_grouped; WORKERS=2; PKT=64; SIZES="256" ;;
        A6-w4)     TYPE=userspace_grouped; WORKERS=4; PKT=64; SIZES="256" ;;
        A6-w8)     TYPE=userspace_grouped; WORKERS=8; PKT=64; SIZES="256" ;;
        *)         printf 'Unknown ablation: %s\n' "$NAME"; return 1 ;;
    esac

    rm -rf "$OUT/$NAME"
    bash "$ROOT/benchmarks/ablation/run_one_ablation.sh" \
        "$NAME" "$TYPE" "$WORKERS" "$PKT" $SIZES

    local LAT="$OUT/$NAME/latency_results.csv"
    local SCAL="$OUT/$NAME/scalability_results.csv"
    local CPU="$OUT/$NAME/cpu_results.txt"
    local META="$OUT/$NAME/metadata.txt"

    local status
    status=$(grep '^status=' "$META" 2>/dev/null | cut -d= -f2)

    local LROWS LFAIL SROWS CPUP
    LROWS=$(grep -cE '^[0-9]' "$LAT"  2>/dev/null) || LROWS=0
    LFAIL=$(grep -c 'FAIL'    "$LAT"  2>/dev/null) || LFAIL=0
    SROWS=$(grep -cE '^[0-9]' "$SCAL" 2>/dev/null) || SROWS=0
    CPUP=0
    [ -s "$CPU" ] && grep -qE 'CPU Utilization|cpu median:' "$CPU" && CPUP=1

    printf '\n=== Validation for %s ===\n' "$NAME"
    printf '  status:            %s\n' "${status:-unknown}"
    printf '  type:              %s\n' "$TYPE"
    printf '  workers:           %s\n' "$WORKERS"
    printf '  latency rows:      %s (fail: %s)\n' "$LROWS" "$LFAIL"
    printf '  scalability rows:  %s\n' "$SROWS"
    printf '  cpu present:       %s\n' "$CPUP"

    local fails=0

    if [ "$status" = "unavailable" ]; then
        printf '  RESULT: OK (unavailable by design - no eBPF loader)\n'
        return 0
    fi
    if [ "$status" != "ok" ]; then
        printf '  RESULT: FAILED - status=%s\n' "$status"
        return 1
    fi

    if [ "$WORKERS" -eq 1 ]; then
        [ "$LROWS" -ge 8 ] || { printf '  RESULT: FAILED - expected >=8 latency rows, got %s\n' "$LROWS"; fails=$((fails+1)); }
        [ "$LFAIL" -eq 0 ] || { printf '  RESULT: FAILED - %s FAIL rows in latency\n' "$LFAIL"; fails=$((fails+1)); }
        [ "$SROWS" -ge 1 ] || { printf '  RESULT: FAILED - expected >=1 scalability row, got %s\n' "$SROWS"; fails=$((fails+1)); }
        [ "$CPUP"  -eq 1 ] || { printf '  RESULT: FAILED - no CPU measurement\n'; fails=$((fails+1)); }
    else
        [ "$SROWS" -ge "$WORKERS" ] || { printf '  RESULT: FAILED - expected %s scalability rows, got %s\n' "$WORKERS" "$SROWS"; fails=$((fails+1)); }
    fi

    if [ "$fails" -eq 0 ]; then
        printf '  RESULT: OK\n'
        return 0
    fi

    printf '  RESULT: FAILED - inspect %s\n' "$OUT/$NAME"
    printf '  --- aggregator.log tail ---\n'
    tail -5 "$OUT/$NAME/aggregator.log" 2>/dev/null | sed 's/^/    /'
    printf '  --- latency_results.csv head ---\n'
    head -3 "$LAT" 2>/dev/null | sed 's/^/    /'
    return 1
}


# ============================================================
# run_preflight
# ============================================================
run_preflight() {
    local pass=0 fail=0
    local ok bad
    ok()  { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
    bad() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

    printf '== Stage 1: environment ==\n'
    local KVER
    KVER=$(uname -r | cut -d. -f1-2)
    awk -v k="$KVER" 'BEGIN { exit !(k >= 5.15) }' \
        && ok "kernel $KVER >= 5.15" || bad "kernel $KVER < 5.15"
    local t
    for t in bpftool ss fuser lsof python3; do
        command -v "$t" >/dev/null 2>&1 && ok "tool $t" || bad "tool $t missing"
    done

    printf '\n== Stage 2: binaries ==\n'
    local b
    for b in benchmarks/build/latency_benchmark \
             benchmarks/build/scalability_benchmark \
             benchmarks/build/cpu_benchmark \
             examples/build/simple_allreduce; do
        [ -x "$ROOT/$b" ] && ok "$b" || bad "$b missing"
    done

    printf '\n== Stage 3: port cleanup ==\n'
    sudo pkill -KILL -f '[u]serspace_aggregator'  >/dev/null 2>&1 || true
    sudo pkill -KILL -f '[e]cho_aggregator'       >/dev/null 2>&1 || true
    command -v fuser >/dev/null 2>&1 && \
        sudo fuser -k -KILL 9999/udp >/dev/null 2>&1 || true
    sleep 1
    ss -lun 2>/dev/null | grep -q ':9999' \
        && bad "port 9999 still busy" || ok "port 9999 free"

    printf '\n== Stage 4: smoke test ==\n'
    if ( run_smoke ) > /tmp/pre_smoke.log 2>&1; then
        ok "smoke test passed"
    else
        bad "smoke test failed (see /tmp/pre_smoke.log)"
    fi

    printf '\n== Stage 5: single-config ablation (A2) ==\n'
    if ( run_one A2 ) > /tmp/pre_a2.log 2>&1; then
        ok "A2 ok=8 fail=0"
    else
        bad "A2 failed (see /tmp/pre_a2.log)"
        tail -20 /tmp/pre_a2.log | sed 's/^/    /'
    fi

    printf '\n===========================================\n'
    printf 'Pre-flight: %d passed, %d failed\n' "$pass" "$fail"
    printf '===========================================\n'
    if [ "$fail" -eq 0 ]; then
        printf 'Safe to run: bash scripts/run_ablation.sh\n'
        return 0
    fi
    return 1
}


# ============================================================
# run_quick
# ============================================================
run_quick() {
    local OUT="$ROOT/benchmarks/results/ablation"
    printf 'Quick ablation pre-flight\n'

    if ! ( run_smoke ); then
        printf 'Smoke test failed. Aborting.\n'
        return 1
    fi

    printf '\nRunning A2 through the real ablation harness\n'
    rm -rf "$OUT/A2" "$OUT/A4"
    bash "$ROOT/benchmarks/ablation/run_one_ablation.sh" \
        A2 userspace 1 64 64 256 1024 4096 16384 65536
    bash "$ROOT/benchmarks/ablation/run_one_ablation.sh" \
        A4 userspace 1 64 64 256 1024 4096 16384 65536

    local LAT="$OUT/A2/latency_results.csv"
    if [ ! -f "$LAT" ]; then
        printf 'FAIL: %s missing\n' "$LAT"
        return 1
    fi
    local ROWS FAILS
    ROWS=$(grep -cE '^[0-9]' "$LAT" 2>/dev/null) || ROWS=0
    FAILS=$(grep -c 'FAIL' "$LAT" 2>/dev/null)   || FAILS=0
    printf 'A2 rows=%s fails=%s\n' "$ROWS" "$FAILS"
    if [ "$ROWS" -lt 8 ] || [ "$FAILS" -gt 0 ]; then
        printf 'Pre-flight FAILED\n'
        return 1
    fi

    local LAT4="$OUT/A4/latency_results.csv"
    local ROWS4 FAILS4
    ROWS4=$(grep -cE '^[0-9]' "$LAT4" 2>/dev/null) || ROWS4=0
    FAILS4=$(grep -c 'FAIL' "$LAT4" 2>/dev/null)   || FAILS4=0
    printf 'A4 rows=%s fails=%s\n' "$ROWS4" "$FAILS4"
    if [ "$ROWS4" -lt 8 ] || [ "$FAILS4" -gt 0 ]; then
        printf 'Pre-flight FAILED\n'
        return 1
    fi

    python3 "$ROOT/benchmarks/ablation/combine_results.py" \
        --input "$OUT" --output "$OUT" >/dev/null 2>&1 || true
    python3 "$ROOT/benchmarks/analysis/plot_ablation.py" \
        --input "$OUT" --output "$OUT" >/dev/null 2>&1 || true

    printf '\nPre-flight PASSED - safe to run full ablation:\n'
    printf '  bash scripts/run_ablation.sh\n'
    return 0
}

# ============================================================
# run_k8s
# ============================================================
run_k8s() {
    echo "Kubernetes KIND test"

    # --- Preconditions ---
    if ! command -v kind >/dev/null 2>&1; then
        echo "kind not found; run scripts/setup.sh"
        return 1
    fi
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "kubectl not found; run scripts/setup.sh"
        return 1
    fi

    # --- Build the operator image ---
    echo "Building operator image..."
    local OP_IMG=ebpf-p4-operator:latest
    ( cd "$ROOT/operator" && make docker-build IMG="$OP_IMG" ) || {
        echo "Operator image build FAILED"
        return 1
    }

    # --- Clean leftovers ---
    echo "Cleaning leftovers"
    sudo docker stop -t 0 ${CLUSTER}-control-plane 2>/dev/null || true
    sudo docker rm -f ${CLUSTER}-control-plane 2>/dev/null || true
    sudo docker network rm kind 2>/dev/null || true
    sudo kind delete cluster --name ${CLUSTER} 2>/dev/null || true

    # --- Create KIND cluster ---
    echo "Creating KIND cluster"
    sudo kind create cluster --name ${CLUSTER} --wait 90s

    # --- Kubeconfig ---
    echo "Copying kubeconfig"
    mkdir -p ~/.kube
    sudo cp /root/.kube/config ~/.kube/config 2>/dev/null || \
        sudo kind export kubeconfig --name ${CLUSTER}
    sudo chown -R "$USER":"$USER" ~/.kube
    chmod 600 ~/.kube/config
    kubectl get nodes

    # --- Load the operator image ---
    echo "Loading operator image into KIND"
    sudo kind load docker-image ${OP_IMG} --name ${CLUSTER}

    # --- Apply manifests ---
    echo "Applying manifests"
    kubectl apply -f operator/config/crd/mlaccel.io_gradientaggregations.yaml
    sleep 2
    kubectl apply -f operator/config/sample/gradientaggregation.yaml
    sleep 2
    kubectl apply -f deploy/operator.yaml
    sleep 5

    echo "Pod status"
    kubectl get pods -n mlaccel-system 2>/dev/null || true
    kubectl get gradientaggregations -A 2>/dev/null || true

    # --- Cleanup ---
    echo "Cleanup"
    sudo kind delete cluster --name ${CLUSTER} 2>/dev/null || true
    echo "Kubernetes test done"
}

# ============================================================
# dispatcher
# ============================================================
MODE=${1:-all}
shift 2>/dev/null || true

case "$MODE" in
    native)     run_native ;;
    docker)     run_docker ;;
    k8s)        run_k8s ;;
    k8s-run)    run_k8s_experiments ;;   # <-- new
    smoke)      run_smoke ;;
    one)        run_one "$@" ;;
    preflight)  run_preflight ;;
    quick)      run_quick ;;
    all)        run_native; run_docker; run_k8s ;;
    *)          echo "Usage: $0 {native|docker|k8s|k8s-run|smoke|one <NAME>|preflight|quick|all}"; exit 1 ;;
esac