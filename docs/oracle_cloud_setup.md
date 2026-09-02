# Oracle Cloud Setup

1. Provision two Ubuntu 22.04 VMs (1 control‑plane, 1 worker) with 4 GB RAM each.
2. Run `scripts/setup_oci_env.sh` on both.
3. On control‑plane, run `scripts/deploy_kind_cluster.sh`.
4. Run `scripts/install_bpfd.sh`.
5. Run `scripts/deploy_operator.sh`.
6. Apply sample CR: `kubectl apply -f operator/config/sample/gradientaggregation.yaml`.
7. Run benchmarks from worker node.