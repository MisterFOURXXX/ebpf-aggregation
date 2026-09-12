#!/bin/bash
# ============================================================
# deploy.sh - UNIFIED Kubernetes deployment:
#   1. Create KIND cluster
#   2. Install bpfd daemonset
#   3. Build + deploy the Operator
# ============================================================
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
CLUSTER=${CLUSTER:-ebpf-p4}
IMG=${IMG:-ebpf-p4-operator:latest}

echo "=============================================="
echo "   Deploy: KIND + bpfd + Operator"
echo "=============================================="

# --- 1. Create KIND cluster ---
echo "[1/3] Creating KIND cluster '$CLUSTER'..."
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
    kind create cluster --name "$CLUSTER" --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF
else
    echo "  Cluster '$CLUSTER' already exists."
fi

# --- 2. Install bpfd ---
echo "[2/3] Installing bpfd..."
kubectl create namespace bpfd 2>/dev/null || true
kubectl apply -f deploy/bpfd-daemonset.yaml
kubectl rollout status daemonset/bpfd -n bpfd --timeout=60s || \
    echo "  [warn] bpfd rollout timed out (may still be starting)"

# --- 3. Build and deploy Operator ---
echo "[3/3] Building and deploying Operator..."
cd "$ROOT/operator"
make docker-build IMG="$IMG"
kind load docker-image "$IMG" --name "$CLUSTER"
make deploy
cd "$ROOT"

echo ""
echo "--- Status ---"
kubectl get pods -n mlaccel-system 2>/dev/null || true
kubectl get pods -n bpfd 2>/dev/null || true
echo ""
echo "Deploy complete."
