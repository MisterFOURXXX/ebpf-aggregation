#!/bin/bash
kubectl create namespace bpfd
kubectl apply -f deploy/bpfd-daemonset.yaml
kubectl rollout status daemonset/bpfd -n bpfd