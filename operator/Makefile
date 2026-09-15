IMG ?= ebpf-p4-operator:latest

.PHONY: all build docker-build deploy undeploy clean

all: build

build:
	go build -o bin/manager main.go

docker-build:
	docker build -t $(IMG) .

deploy: docker-build
	kind load docker-image $(IMG) --name ebpf-p4 || true
	kubectl apply -f config/crd/mlaccel.io_gradientaggregations.yaml
	kubectl apply -f deploy/operator.yaml

undeploy:
	kubectl delete -f deploy/operator.yaml --ignore-not-found
	kubectl delete -f config/crd/mlaccel.io_gradientaggregations.yaml --ignore-not-found

clean:
	rm -rf bin