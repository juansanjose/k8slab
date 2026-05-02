#!/bin/bash
set -e

# MLOps Lab - Container Abstraction Layer
# Bridges Kubernetes (local) and SkyPilot (cloud GPU)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Build training container
build_container() {
    log_info "Building training container..."
    
    cd "$PROJECT_ROOT"
    
    # Check if local registry exists
    if ! kubectl get svc docker-registry -n kube-system > /dev/null 2>&1; then
        log_info "Setting up local Docker registry..."
        kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: docker-registry
  namespace: kube-system
spec:
  selector:
    app: docker-registry
  ports:
  - port: 5000
    targetPort: 5000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docker-registry
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      containers:
      - name: registry
        image: registry:2
        ports:
        - containerPort: 5000
EOF
        sleep 5
    fi
    
    # Build and push
    docker build -t localhost:5000/mlops-training:latest .
    docker push localhost:5000/mlops-training:latest
    
    log_success "Container built and pushed"
}

# Deploy Kubernetes resources
deploy_k8s() {
    log_info "Deploying Kubernetes resources..."
    
    cd "$PROJECT_ROOT"
    
    # Apply configs
    kubectl apply -f k8s/configs.yaml
    kubectl apply -f k8s/training-job.yaml
    
    log_success "Kubernetes resources deployed"
}

# Run training via SkyPilot with container abstraction
run_cloud_training() {
    local job_type=$1
    local cluster_name="${2:-gpu-training}"
    
    log_info "Starting cloud GPU training with container abstraction..."
    
    # Generate SkyPilot task from template
    cat > /tmp/skypilot-task.yaml <<EOF
resources:
  cloud: runpod
  accelerators: L4:1
  disk_size: 80
  image_id: docker:localhost:5000/mlops-training:latest

envs:
  MLFLOW_TRACKING_URI: http://localhost:30500
  MLFLOW_S3_ENDPOINT_URL: http://localhost:30900
  AWS_ACCESS_KEY_ID: minioadmin
  AWS_SECRET_ACCESS_KEY: minioadmin123
  MODEL_NAME: TinyLlama/TinyLlama-1.1B-Chat-v1.0
  DATASET_NAME: tatsu-lab/alpaca
  NUM_EPOCHS: "1"
  BATCH_SIZE: "2"
  LEARNING_RATE: "2e-4"
  HF_HOME: /workspace/huggingface_cache

run: |
  cd /workspace
  python3 train_llm.py
EOF
    
    cd "$PROJECT_ROOT/skypilot/tasks"
    
    if sky status | grep -q "$cluster_name"; then
        log_info "Reusing existing cluster..."
        echo "y" | sky exec "$cluster_name" /tmp/skypilot-task.yaml
    else
        log_info "Provisioning new GPU instance..."
        sky launch -c "$cluster_name" /tmp/skypilot-task.yaml --yes
    fi
}

# Check cluster health
check_health() {
    log_info "Checking cluster health..."
    
    echo ""
    echo "Kubernetes Status:"
    kubectl get nodes
    echo ""
    echo "MLOps Services:"
    kubectl get pods -n mlops
    echo ""
    echo "SkyPilot Status:"
    sky check
}

# Cleanup resources
cleanup() {
    log_warn "Cleaning up resources..."
    
    read -p "Are you sure? This will delete all training jobs and clusters. [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sky down -a -y
        kubectl delete -f "$PROJECT_ROOT/k8s/training-job.yaml" --ignore-not-found
        log_success "Cleanup complete"
    else
        log_info "Cleanup cancelled"
    fi
}

# Main
case "${1:-help}" in
    "build")
        build_container
        ;;
    "deploy")
        deploy_k8s
        ;;
    "run"|"train")
        run_cloud_training "${2:-llm}" "${3:-}"
        ;;
    "health"|"status")
        check_health
        ;;
    "cleanup")
        cleanup
        ;;
    "help"|*)
        echo "MLOps Lab - Container Abstraction Layer"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  build              - Build training container"
        echo "  deploy             - Deploy Kubernetes resources"
        echo "  run [type] [name]  - Run training job (type: llm, bert)"
        echo "  health             - Check cluster health"
        echo "  cleanup            - Clean up all resources"
        echo ""
        ;;
esac
