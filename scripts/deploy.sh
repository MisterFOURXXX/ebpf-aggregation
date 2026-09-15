#!/bin/bash
# ============================================================
# deploy.sh - KIND cluster + bpfd + Operator
# ============================================================
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
CLUSTER=${CLUSTER:-ebpf-p4}
IMG=${IMG:-ebpf-p4-operator:latest}

printf '==============================================\n'
printf '   Deploy: KIND + bpfd + Operator\n'
printf '==============================================\n'
printf '  Cluster: %s\n' "$CLUSTER"
printf '  Image:   %s\n\n' "$IMG"

# --- 0. Sanity check: image must build before we create a cluster ---
printf '[0/3] Building operator image first\n'
(cd "$ROOT/operator" && make docker-build IMG="$IMG") || {
    printf '\n[ERROR] Operator image build FAILED.\n'
    printf 'Diagnose with:\n'
    printf '  cd %s/operator && make docker-build IMG=%s\n' "$ROOT" "$IMG"
    exit 1
}

# --- 1. KIND cluster ---
printf '\n[1/3] KIND cluster %s\n' "$CLUSTER"
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
    printf '  Cluster already exists\n'
fi

# --- 2. bpfd (optional) ---
printf '\n[2/3] bpfd DaemonSet (optional)\n'
kubectl create namespace bpfd 2>/dev/null || true
kubectl apply -f "$ROOT/deploy/bpfd-daemonset.yaml"
if ! kubectl rollout status daemonset/bpfd -n bpfd --timeout=60s 2>/dev/null; then
    printf '  [warn] bpfd did not become Ready (expected on KIND)\n'
    printf '  [warn] Continuing without bpfd\n'
fi

# --- 3. Operator ---
printf '\n[3/3] Loading image and deploying operator\n'
kind load docker-image "$IMG" --name "$CLUSTER"
kubectl apply -f "$ROOT/operator/config/crd/mlaccel.io_gradientaggregations.yaml"
kubectl apply -f "$ROOT/deploy/operator.yaml"
kubectl apply -f "$ROOT/operator/config/sample/gradientaggregation.yaml"

sleep 5
printf '\n--- Status ---\n'
kubectl get pods -n mlaccel-system 2>/dev/null || true
kubectl get gradientaggregations -A 2>/dev/null || true
printf '\nDeploy complete.\n'