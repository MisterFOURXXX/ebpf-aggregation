#!/bin/bash
cd operator
make docker-build IMG=ebpf-p4-operator:latest
kind load docker-image ebpf-p4-operator:latest --name ebpf-p4
make deploy