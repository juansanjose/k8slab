#!/bin/bash
# SkyPilot Helper Scripts for Hybrid MLOps Lab
# Source this file: source skypilot/scripts/skypilot-helpers.sh

# ==================== Configuration ====================
export SKYPILOT_DIR="/home/juan/k8s/mlops-lab/skypilot"
export MLFLOW_URI="http://100.87.186.22:30500"
export MINIO_URI="http://100.87.186.22:30900"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# ==================== Quick Commands ====================

# Test GPU connectivity on RunPod (cheapest, ~$0.01)
skypilot-test() {
    echo "Launching GPU test on RunPod..."
    cd "$SKYPILOT_DIR"
    sky launch tasks/gpu-test-runpod.yaml -c gpu-test --yes --down
}

# Run LLM training on RunPod
skypilot-train-llm() {
    local model="${1:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}"
    local epochs="${2:-1}"
    
    echo "Launching LLM training on RunPod: model=$model, epochs=$epochs"
    cd "$SKYPILOT_DIR"
    
    MODEL_NAME="$model" NUM_EPOCHS="$epochs" \
        sky launch tasks/train-llm-runpod.yaml -c llm-train --yes
}

# Run BERT training on RunPod
skypilot-train-bert() {
    echo "Launching BERT classification training on RunPod..."
    cd "$SKYPILOT_DIR"
    sky launch tasks/train-bert-runpod.yaml -c bert-train --yes
}

# Check status
skypilot-status() {
    echo "=== SkyPilot Clusters ==="
    sky status
    echo ""
    echo "=== Cost Estimate ==="
    sky status --all | grep -E "(CLUSTER|HOURLY_PRICE)" || echo "No active clusters"
}

# Stop cluster (preserve disk)
skypilot-stop() {
    local cluster="${1:-gpu-test}"
    echo "Stopping cluster: $cluster"
    sky stop "$cluster" --yes
}

# Terminate cluster (release GPU, delete disk)
skypilot-down() {
    local cluster="${1:-gpu-test}"
    echo "Terminating cluster: $cluster"
    sky down "$cluster" --yes
}

# Auto-shutdown after idle minutes
skypilot-autostop() {
    local cluster="${1:-llm-train}"
    local minutes="${2:-30}"
    echo "Setting autostop for $cluster after $minutes minutes idle..."
    sky autostop "$cluster" -i "$minutes"
}

# ==================== MLOps Integration ====================

mlflow-check() {
    echo -n "MLflow ($MLFLOW_URI): "
    curl -s --max-time 3 "$MLFLOW_URI" > /dev/null && echo "OK" || echo "FAIL"
}

mlflow-ui() {
    echo "Opening MLflow UI at $MLFLOW_URI"
    xdg-open "$MLFLOW_URI" 2>/dev/null || echo "Open: $MLFLOW_URI"
}

minio-check() {
    echo -n "MinIO ($MINIO_URI): "
    curl -s --max-time 3 "$MINIO_URI/minio/health/live" > /dev/null && echo "OK" || echo "FAIL"
}

minio-ui() {
    echo "Opening MinIO console at $MINIO_URI"
    xdg-open "$MINIO_URI" 2>/dev/null || echo "Open: $MINIO_URI"
}

# ==================== Kubernetes ====================

k8s-status() {
    echo "=== Kubernetes Services ==="
    kubectl get pods -n mlops
    echo ""
    echo "=== Kubeflow ==="
    kubectl get pods -n kubeflow
}

k8s-logs() {
    local service="${1:-mlflow}"
    local namespace="${2:-mlops}"
    kubectl logs -n "$namespace" deployment/"$service" --tail=50
}

# ==================== Cost Tracking ====================

skypilot-costs() {
    echo "=== Current SkyPilot Costs ==="
    sky status --all 2>/dev/null | grep -E "(CLUSTER|RESOURCES|HOURLY_PRICE|STATUS)" || echo "No clusters running"
    echo ""
    echo "Note: Costs shown are hourly rates. Total = hours_running x hourly_rate"
}

# ==================== Help ====================

skypilot-help() {
    cat << 'EOF'
SkyPilot Helper Commands (RunPod Backend)
==========================================

GPU Tasks:
  skypilot-test              - Test GPU on RunPod (~$0.01, 2-5 min)
  skypilot-train-llm [m] [e] - LLM fine-tuning on RunPod
  skypilot-train-bert        - BERT classification on RunPod

Cluster Management:
  skypilot-status            - Show all clusters
  skypilot-stop [cluster]    - Stop (keep disk)
  skypilot-down [cluster]    - Terminate (delete all)
  skypilot-autostop [c] [m]  - Auto-shutdown after idle minutes

MLOps Services:
  mlflow-check               - Check MLflow connectivity
  mlflow-ui                  - Open MLflow UI
  minio-check                - Check MinIO connectivity
  minio-ui                   - Open MinIO console

Kubernetes:
  k8s-status                 - Show k3s services
  k8s-logs [svc] [ns]        - View logs

Cost:
  skypilot-costs             - Show current spending

Note: Backend is RunPod. Vast.ai tasks exist but require PR fixes.
      See docs/VASTAI_PR_DOCUMENTATION.md for details.

EOF
}

echo "SkyPilot helpers loaded (RunPod backend). Run 'skypilot-help' for commands."