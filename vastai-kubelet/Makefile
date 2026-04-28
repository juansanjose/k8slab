.PHONY: all build docker deploy clean

IMAGE ?= vastai-kubelet
TAG ?= latest

all: build

build:
	go build -o bin/virtual-kubelet ./cmd/virtual-kubelet

docker:
	docker build -t $(IMAGE):$(TAG) .

dep:
	go mod tidy

deploy: docker
	kubectl apply -f deploy/rbac.yaml
	kubectl apply -f deploy/secret.yaml
	kubectl apply -f deploy/deployment.yaml

clean:
	rm -rf bin/
	kubectl delete -f deploy/ || true