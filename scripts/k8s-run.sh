#!/bin/bash
# ============================================================
# k8s-run.sh
#
#   bash scripts/k8s-run.sh          # exp + abl + 6-panel report
#   bash scripts/k8s-run.sh exp      # experiments only
#   bash scripts/k8s-run.sh abl      # ablation only (full 11 configs)
#   bash scripts/k8s-run.sh test     # FAST A2+A4 validation (~3 min)
#   bash scripts/k8s-run.sh plot     # regenerate plots only
#   bash scripts/k8s-run.sh clean    # delete cluster + k8s-results
# ============================================================
set +m
set +e
cd "$(dirname "$0")/.."
ROOT=$(pwd)

CLUSTER=ebpf-p4
AGG_IMG=ebpf-p4-agg:latest
OP_IMG=ebpf-p4-operator:latest
RESULT_DIR="$ROOT/k8s-results"
PVC=ebpf-p4-results
READER=ebpf-p4-reader

MODE=${1:-all}

# ------------------------------------------------------------
# Cleanup / ownership helpers (always sudo-safe)
# ------------------------------------------------------------
cleanup_cluster() {
    echo "[clean] Deleting cluster $CLUSTER"
    kind delete cluster --name "$CLUSTER" 2>/dev/null || true
    kind delete cluster --name ebpf-test 2>/dev/null || true
    echo "[clean] Removing $RESULT_DIR"
    sudo rm -rf "$RESULT_DIR" 2>/dev/null || rm -rf "$RESULT_DIR" 2>/dev/null || true
}

reclaim_results() {
    [ -d "$RESULT_DIR" ] && sudo chown -R "$USER":"$USER" "$RESULT_DIR" 2>/dev/null || true
}

prepare_dir() {
    local d=$1
    sudo rm -rf "$d" 2>/dev/null || rm -rf "$d" 2>/dev/null || true
    sudo mkdir -p "$d" 2>/dev/null || mkdir -p "$d"
    sudo chown -R "$USER":"$USER" "$d" 2>/dev/null || true
}

case "$MODE" in
    clean) cleanup_cluster; exit 0 ;;
    plot)
        reclaim_results
        echo "[plot] Regenerating plots from $RESULT_DIR"
        sudo docker run --rm \
            -v "$RESULT_DIR:/data" \
            -v "$ROOT/scripts:/app/scripts:ro" \
            -v "$ROOT/benchmarks/analysis:/app/benchmarks/analysis:ro" \
            "$AGG_IMG" \
            bash -c '
                python3 /app/scripts/plot_k8s_results.py --root /data
                if [ -d /data/ablation/ablation ]; then
                    python3 /app/benchmarks/analysis/plot_ablation.py \
                        --input  /data/ablation/ablation \
                        --output /data/ablation/ablation
                fi
            '
        reclaim_results
        exit 0
        ;;
esac

# ------------------------------------------------------------
# Reader pod
# ------------------------------------------------------------
start_reader_pod() {
    kubectl delete pod "$READER" --ignore-not-found >/dev/null 2>&1
    cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $READER
  namespace: default
spec:
  restartPolicy: Never
  containers:
  - name: reader
    image: busybox:1.36
    imagePullPolicy: IfNotPresent
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: results
      mountPath: /results
  volumes:
  - name: results
    persistentVolumeClaim:
      claimName: $PVC
EOF
    local i=0
    while [ $i -lt 60 ]; do
        phase=$(kubectl get pod "$READER" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$phase" = "Running" ]; then
            echo "  reader pod Running"
            return 0
        fi
        sleep 1; i=$((i+1))
    done
    echo "  [warn] reader pod not Running after 60 s"
    kubectl describe pod "$READER" 2>/dev/null | tail -20 | sed 's/^/    /'
    return 1
}

stop_reader_pod() {
    kubectl delete pod "$READER" --ignore-not-found >/dev/null 2>&1
}

copy_from_reader() {
    local dest=$1
    prepare_dir "$dest"
    echo "  copying $READER:/results -> $dest"
    kubectl cp "default/${READER}:/results/." "$dest/" 2>&1 | sed 's/^/    /'
    reclaim_results
    echo "  host listing:"
    find "$dest" -maxdepth 4 -type f 2>/dev/null | sed 's/^/    /' | head -60
}

# ------------------------------------------------------------
# Build helper
# ------------------------------------------------------------
build_image_if_missing() {
    local img=$1
    local ctx=$2
    if sudo docker image inspect "$img" >/dev/null 2>&1; then
        echo "  $img present"
        return 0
    fi
    echo "  building $img"
    sudo docker build -t "$img" "$ctx" >/dev/null || {
        echo "  FATAL: build failed for $img"; return 1
    }
}

# ------------------------------------------------------------
# Plot helpers (always use host scripts via volume mount)
# ------------------------------------------------------------
run_plots() {
    reclaim_results
    echo "[7/8] Generating plots"
    sudo docker run --rm \
        -v "$RESULT_DIR:/data" \
        -v "$ROOT/scripts:/app/scripts:ro" \
        -v "$ROOT/benchmarks/analysis:/app/benchmarks/analysis:ro" \
        "$AGG_IMG" \
        bash -c '
            echo "--- experiment plots ---"
            python3 /app/scripts/plot_k8s_results.py --root /data
            echo "--- ablation 6-panel report ---"
            if [ -d /data/ablation/ablation ]; then
                python3 /app/benchmarks/analysis/plot_ablation.py \
                    --input  /data/ablation/ablation \
                    --output /data/ablation/ablation
            else
                echo "  [skip] /data/ablation/ablation not found"
            fi
        ' 2>&1 | grep -v Matplotlib
    reclaim_results
}

# ------------------------------------------------------------
# 0. Clean leftover cluster only
# ------------------------------------------------------------
echo "[0/8] Cleaning leftover cluster"
kind delete cluster --name "$CLUSTER"  2>/dev/null || true
kind delete cluster --name ebpf-test   2>/dev/null || true

# ------------------------------------------------------------
# 1. Build images if missing
# ------------------------------------------------------------
echo "[1/8] Checking images"
build_image_if_missing "$AGG_IMG" "$ROOT"            || exit 1
build_image_if_missing "$OP_IMG"  "$ROOT/operator"   || exit 1

# ------------------------------------------------------------
# 2. Create cluster
# ------------------------------------------------------------
echo "[2/8] Creating KIND cluster"
kind create cluster --name "$CLUSTER" --wait 90s
kind export kubeconfig --name "$CLUSTER" >/dev/null

# ------------------------------------------------------------
# 3. Load images
# ------------------------------------------------------------
echo "[3/8] Loading images into KIND"
kind load docker-image "$AGG_IMG" --name "$CLUSTER"
kind load docker-image "$OP_IMG"  --name "$CLUSTER"

# ------------------------------------------------------------
# 4. Deploy operator
# ------------------------------------------------------------
echo "[4/8] Applying CRD + operator + sample"
kubectl apply -f "$ROOT/operator/config/crd/mlaccel.io_gradientaggregations.yaml"
kubectl apply -f "$ROOT/deploy/operator.yaml"
kubectl apply -f "$ROOT/operator/config/sample/gradientaggregation.yaml"
sleep 5
kubectl get pods -n mlaccel-system
kubectl get gradientaggregations -A

# ------------------------------------------------------------
# 5. Experiments
# ------------------------------------------------------------
if [ "$MODE" = "all" ] || [ "$MODE" = "exp" ]; then
    echo "[5/8] Experiments"
    kubectl delete job ebpf-p4-experiments --ignore-not-found >/dev/null
    kubectl delete pvc "$PVC" --ignore-not-found >/dev/null
    sleep 2

    kubectl apply -f "$ROOT/deploy/experiment-job.yaml"

    echo "  waiting (max 20 min)"
    if kubectl wait --for=condition=complete job/ebpf-p4-experiments \
            --timeout=20m >/dev/null 2>&1; then
        echo "  job Complete"
    else
        echo "  [warn] job did not complete"
        kubectl logs job/ebpf-p4-experiments --tail=60 | sed 's/^/    /'
    fi

    if start_reader_pod; then
        copy_from_reader "$RESULT_DIR/experiments"
    fi
    stop_reader_pod
fi

# ------------------------------------------------------------
# 5b. Fast test mode (A2 + A4 only) – self-contained, ~3 min
# ------------------------------------------------------------
if [ "$MODE" = "test" ]; then
    echo "[5/8] Test mode: A2 + A4 validation (self-contained)"
    kubectl delete job ebpf-p4-test --ignore-not-found >/dev/null 2>&1
    kubectl delete pvc "$PVC" --ignore-not-found >/dev/null 2>&1
    sleep 3

    kubectl apply -f "$ROOT/deploy/test-job.yaml"

    echo "  waiting (max 8 min)"
    if kubectl wait --for=condition=complete job/ebpf-p4-test \
            --timeout=8m >/dev/null 2>&1; then
        echo "  job Complete"
    else
        echo "  [warn] test job timed out – dumping logs"
        kubectl logs job/ebpf-p4-test --tail=100 2>/dev/null | sed 's/^/    /' || true
    fi

    if start_reader_pod; then
        copy_from_reader "$RESULT_DIR/ablation"
    fi
    stop_reader_pod

    echo "[TEST] Verifying results:"
    # Look for files in any reasonable location
    A2_LAT=$(find "$RESULT_DIR" -path '*/A2/latency_results.csv' 2>/dev/null | head -1)
    A4_LAT=$(find "$RESULT_DIR" -path '*/A4/latency_results.csv' 2>/dev/null | head -1)

    A2_OK=0; A4_OK=0
    [ -n "$A2_LAT" ] && [ -s "$A2_LAT" ] && A2_OK=1
    [ -n "$A4_LAT" ] && [ -s "$A4_LAT" ] && A4_OK=1

    echo "  A2 latency: $([ $A2_OK -eq 1 ] && echo OK || echo MISSING)  ${A2_LAT:-<not found>}"
    echo "  A4 latency: $([ $A4_OK -eq 1 ] && echo OK || echo MISSING)  ${A4_LAT:-<not found>}"

    if [ $A2_OK -eq 1 ] && [ $A4_OK -eq 1 ]; then
        echo "[TEST] PASSED – harness works. You may now run the full ablation:"
        echo "        bash scripts/k8s-run.sh abl"
        echo "     or the complete pipeline:"
        echo "        bash scripts/k8s-run.sh"
    else
        echo "[TEST] FAILED"
        echo "  Directory tree:"
        find "$RESULT_DIR" -type d 2>/dev/null | sed 's/^/    /' || true
        echo "  Job logs (last 80 lines):"
        kubectl logs job/ebpf-p4-test --tail=80 2>/dev/null | sed 's/^/    /' || true
    fi
    exit 0
fi

# ------------------------------------------------------------
# 6. Ablation (full 11 configs)
# ------------------------------------------------------------
if [ "$MODE" = "all" ] || [ "$MODE" = "abl" ]; then
    echo "[6/8] Ablation (full 11 configs)"
    kubectl delete job ebpf-p4-ablation --ignore-not-found >/dev/null
    # Re-use existing PVC if present; otherwise the job YAML creates it
    kubectl apply -f "$ROOT/deploy/ablation-job.yaml"

    echo "  waiting (max 45 min)"
    if kubectl wait --for=condition=complete job/ebpf-p4-ablation \
            --timeout=45m >/dev/null 2>&1; then
        echo "  job Complete"
    else
        echo "  [warn] job did not complete"
        kubectl logs job/ebpf-p4-ablation --tail=80 | sed 's/^/    /'
    fi

    if start_reader_pod; then
        copy_from_reader "$RESULT_DIR/ablation"
    fi
    stop_reader_pod
fi

# ------------------------------------------------------------
# 7. Plots (experiment 3-plots + 6-panel ablation report)
# ------------------------------------------------------------
run_plots
echo "--- Plotting ablatuin studies ---"
if [ -d /data/ablation ]; then
    # Accept both flat (A2, A4, …) and nested (ablation/A2, …) layouts
    python3 /app/benchmarks/analysis/plot_ablation.py \
        --input  /data/ablation \
        --output /data/ablation
else
    echo "  [skip] /data/ablation not found"
fi

# ------------------------------------------------------------
# 8. Summary
# ------------------------------------------------------------
echo "[8/8] Summary"
echo "  CSVs:"
find "$RESULT_DIR" -maxdepth 5 -name '*.csv' 2>/dev/null | sed 's/^/    /' | head -30
echo "  plots:"
find "$RESULT_DIR" -name '*.png' 2>/dev/null | sed 's/^/    /'
echo "  ablation report:"
ls -la "$RESULT_DIR/ablation/ablation/ablation_report.png" 2>/dev/null \
    | sed 's/^/    /' || echo "    (not produced)"

echo "Done."