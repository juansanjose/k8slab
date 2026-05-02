.PHONY: help setup build deploy train status logs cleanup local-dev

# Default target
help:
	@echo "MLOps Lab - Hybrid Cloud-Native MLOps"
	@echo ""
	@echo "Setup:"
	@echo "  make setup              - Full automated setup (requires sudo)"
	@echo "  make build              - Build training container"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy             - Deploy to Kubernetes"
	@echo "  make local-dev          - Start local development stack"
	@echo ""
	@echo "Training:"
	@echo "  make train              - Submit LLM training job"
	@echo "  make train-bert         - Submit BERT training job"
	@echo "  make test-gpu           - Run GPU connectivity test"
	@echo ""
	@echo "Monitoring:"
	@echo "  make status             - Check cluster and services status"
	@echo "  make logs               - View training logs"
	@echo "  make mlflow             - Open MLflow UI"
	@echo ""
	@echo "Cleanup:"
	@echo "  make cleanup            - Remove all cloud resources"
	@echo "  make stop-local         - Stop local development stack"
	@echo ""

# Setup secrets first
secrets:
	@./mlops-lab/scripts/secrets-setup.sh

# Setup everything (after secrets)
setup: secrets
	@echo ""
	@echo "=== MLOps Lab Setup ==="
	@echo "This will install k3s, deploy services, and configure SkyPilot"
	@echo ""
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		sudo ./scripts/setup.sh; \
	else \
		echo "Setup cancelled"; \
	fi

# Build container
build:
	@echo "=== Building Training Container ==="
	./scripts/cloud-native.sh build

# Deploy to k8s
deploy:
	@echo "=== Deploying to Kubernetes ==="
	./scripts/cloud-native.sh deploy

# Start local development stack (Docker Compose)
local-dev:
	@echo "=== Starting Local Development Stack ==="
	docker-compose --profile local-dev up -d
	@echo ""
	@echo "Services:"
	@echo "  MLflow: http://localhost:30500"
	@echo "  MinIO:  http://localhost:30901"

# Stop local development
stop-local:
	@echo "=== Stopping Local Development Stack ==="
	docker-compose --profile local-dev down

# Training jobs
train:
	@echo "=== Submitting LLM Training Job ==="
	./scripts/train.sh llm

train-bert:
	@echo "=== Submitting BERT Training Job ==="
	./scripts/train.sh bert

test-gpu:
	@echo "=== Running GPU Test ==="
	./scripts/train.sh test

# Status and monitoring
status:
	@echo "=== Cluster Status ==="
	./scripts/cloud-native.sh health

logs:
	@echo "=== Training Logs ==="
	@sky queue gpu-training 2>/dev/null || echo "No active training jobs"
	@echo ""
	@echo "For detailed logs: sky logs gpu-training"

mlflow:
	@echo "Opening MLflow UI..."
	@python3 -c "import webbrowser; webbrowser.open('http://localhost:30500')" 2>/dev/null || \
	echo "Open: http://localhost:30500"

# Cleanup
cleanup:
	@echo "=== Cleaning Up Resources ==="
	./scripts/cloud-native.sh cleanup

# Advanced commands
run-custom:
	@echo "Usage: make run-custom TASK=path/to/task.yaml CLUSTER=my-cluster"
	@if [ -z "$(TASK)" ]; then \
		echo "Error: TASK variable not set"; \
		exit 1; \
	fi
	@sky launch -c $(or $(CLUSTER),custom-training) $(TASK) --yes
