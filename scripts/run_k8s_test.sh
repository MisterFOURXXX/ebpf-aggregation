#!/bin/bash
cd "$(dirname "$0")/.."
ROOT=$(pwd)
CLUSTER=ebpf-test
IMG=ebpf-p4-agg:latest

echo "=============================================="
echo "   Kubernetes (KIND) test"
echo "=============================================="

echo "[1/7] Cleaning leftovers..."
sudo docker stop -t 0 ${CLUSTER}-control-plane 2>/dev/null || true
sudo docker rm -f ${CLUSTER}-control-plane 2>/dev/null || true
sudo docker network rm kind 2>/dev/null || true
sudo kind delete cluster --name ${CLUSTER} 2>/dev/null || true

echo "[2/7] Verifying Docker image..."
if ! sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMG}$"; then
    sudo docker build -t $IMG . > /dev/null
else
    echo "  $IMG already built ✓"
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
kubectl get gradientaggregations -A

echo ""
echo "[7/7] Cleanup..."
sudo kind delete cluster --name ${CLUSTER} 2>/dev/null || {
    sudo docker stop -t 0 ${CLUSTER}-control-plane 2>/dev/null || true
    sudo docker rm -f ${CLUSTER}-control-plane 2>/dev/null || true
    sudo docker network rm kind 2>/dev/null || true
}

echo ""
echo "=== DONE ==="
