#!/bin/bash
# ============================================================
# test.sh - UNIFIED testing
#   Usage:
#     ./scripts/test.sh            # run all (native + docker + k8s)
#     ./scripts/test.sh native     # native benchmarks only
#     ./scripts/test.sh docker     # Docker integration only
#     ./scripts/test.sh k8s        # Kubernetes/KIND only
# ============================================================
set +m
set +b
cd "$(dirname "$0")/.."
ROOT=$(pwd)
LOG="$ROOT/benchmarks/results"
IMG=ebpf-p4-agg:latest
CLUSTER=ebpf-test
MODE=${1:-all}

mkdir -p "$LOG"

# ============================================================
# Native tests
# ============================================================
run_native() {
    echo ""
    echo "=== Native test suite ==="

    ./scripts/clean.sh > /dev/null 2>&1 || true
    ./scripts/build.sh > /dev/null 2>&1 || { echo "Build FAILED"; return 1; }
    mkdir -p "$LOG"

    echo "--- Unit tests ---"
    (cd "$ROOT/tests/build" && ctest 2>&1 | tail -3)

    pkill -f userspace_aggregator 2>/dev/null || true
    sleep 1
    python3 benchmarks/ablation/userspace_aggregator_silent.py > /dev/null 2>&1 &
    AGG_PID=$!
    sleep 2
    kill -0 $AGG_PID 2>/dev/null || { echo "Aggregator failed"; return 1; }

    echo "--- Example (20s) ---"
    (cd "$ROOT/examples/build" && timeout 20 ./simple_allreduce 127.0.0.1 9999 0) \
        | tee "$LOG/example.txt" || echo "  (timeout)"

    echo "--- Latency (30s) ---"
    (cd "$ROOT/benchmarks/build" && timeout 30 ./latency_benchmark 127.0.0.1 9999 0) \
        | tee "$LOG/latency_results.csv" || echo "  (timeout)"

    echo "--- Scalability (20s) ---"
    (cd "$ROOT/benchmarks/build" && timeout 20 ./scalability_benchmark 127.0.0.1 9999 2) \
        | tee "$LOG/scalability_results.csv" || echo "  (timeout)"

    echo "--- CPU (15s) ---"
    (cd "$ROOT/benchmarks/build" && timeout 15 ./cpu_benchmark 127.0.0.1 9999 0 $AGG_PID) \
        | tee "$LOG/cpu_results.txt" || echo "  (timeout)"

    pkill -f userspace_aggregator 2>/dev/null || true
    echo "Native tests done. Results in $LOG"
}

# ============================================================
# Docker test
# ============================================================
run_docker() {
    echo ""
    echo "=== Docker test ==="
    echo "[1/2] Build image..."
    sudo docker build -t $IMG . > /dev/null 2>&1

    echo "[2/2] Run integration test..."
    sudo docker run --rm --privileged --network host $IMG \
        bash -c "cd /app && \
                 pkill -f userspace_aggregator 2>/dev/null; \
                 python3 benchmarks/ablation/userspace_aggregator_silent.py & \
                 sleep 2; \
                 cd examples/build && timeout 20 ./simple_allreduce 127.0.0.1 9999 0; \
                 pkill -f userspace_aggregator"
    echo "Docker test done."
}

# ============================================================
# Kubernetes test
# ============================================================
run_k8s() {
    echo ""
    echo "=== Kubernetes (KIND) test ==="

    echo "[1/7] Cleaning leftovers..."
    sudo docker stop -t 0 ${CLUSTER}-control-plane 2>/dev/null || true
    sudo docker rm -f ${CLUSTER}-control-plane 2>/dev/null || true
    sudo docker network rm kind 2>/dev/null || true
    sudo kind delete cluster --name ${CLUSTER} 2>/dev/null || true

    echo "[2/7] Verifying Docker image..."
    if ! sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMG}$"; then
        sudo docker build -t $IMG . > /dev/null
    else
        echo "  $IMG already built"
    fi

    echo "[3/7] Creating KIND cluster..."
    sudo kind create cluster --name ${CLUSTER} --wait 90s

    echo "[4/7] Copying kubeconfig..."
    mkdir -p ~/.kube
    sudo cp /root/.kube/config ~/.kube/config
    sudo chown -R $USER:$USER ~/.kube
    chmod 600 ~/.kube/config
    kubectl get nodes

    echo "[5/7] Loading image into KIND..."
    sudo kind load docker-image ${IMG} --name ${CLUSTER}

    echo "[6/7] Applying manifests..."
    kubectl apply -f operator/config/crd/mlaccel.io_gradientaggregations.yaml
    sleep 3
    kubectl apply -f deploy/operator.yaml
    sleep 5
    kubectl apply -f operator/config/sample/gradientaggregation.yaml
    sleep 5

    echo ""
    echo "--- Status ---"
    kubectl get pods -n mlaccel-system
    kubectl get crd | grep mlaccel
    kubectl get aggregations 2>/dev/null || \
        kubectl get gradientaggregations -A

    echo ""
    echo "[7/7] Cleanup..."
    sudo kind delete cluster --name ${CLUSTER} 2>/dev/null || {
        sudo docker stop -t 0 ${CLUSTER}-control-plane 2>/dev/null || true
        sudo docker rm -f ${CLUSTER}-control-plane 2>/dev/null || true
        sudo docker network rm kind 2>/dev/null || true
    }
    echo "Kubernetes test done."
}

# ============================================================
# Dispatch
# ============================================================
case "$MODE" in
    native)  run_native ;;
    docker)  run_docker ;;
    k8s)     run_k8s ;;
    all)     run_native; run_docker; run_k8s ;;
    *)       echo "Usage: $0 {native|docker|k8s|all}"; exit 1 ;;
esac
