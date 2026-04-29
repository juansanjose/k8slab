#!/bin/bash
# SkyPilot helper scripts for the hybrid MLOps lab
# Source this file: source skypilot-helpers.sh

# ==================== Configuration ====================
export SKYPILOT_DIR="/home/juan/k8s/mlops-lab/skypilot"
export MLFLOW_URI="http://100.87.186.22:30500"
export MINIO_URI="http://100.87.186.22:30900"

# ==================== Quick Commands ====================

# Test GPU connectivity and basic setup
skypilot-test() {
    echo "Launching GPU test on Vast.ai..."
    cd "$SKYPILOT_DIR"
    sky launch gpu_test.yaml -c gpu-test --yes --down
}

# Run LLM training task
skypilot-train() {
    local model="${1:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}"
    local epochs="${2:-1}"
    
    echo "Launching LLM training: model=$model, epochs=$epochs"
    cd "$SKYPILOT_DIR"
    
    # Override defaults via env
    MODEL_NAME="$model" NUM_EPOCHS="$epochs" \
        sky launch train_llm.yaml -c llm-train --yes
}

# Check status of all SkyPilot clusters
skypilot-status() {
    echo "=== SkyPilot Cluster Status ==="
    sky status
    echo ""
    echo "=== Vast.ai Instances ==="
    sky status --all
}

# Stop a specific cluster
skypilot-stop() {
    local cluster="${1:-gpu-test}"
    echo "Stopping cluster: $cluster"
    sky stop "$cluster" --yes
}

# Terminate a specific cluster (releases GPU instance)
skydown() {
    local cluster="${1:-gpu-test}"
    echo "Terminating cluster: $cluster"
    sky down "$cluster" --yes
}

# Cost estimate before launching
skypilot-cost() {
    local task="${1:-gpu_test.yaml}"
    echo "Estimating cost for $task..."
    cd "$SKYPILOT_DIR"
    sky show-gpus --cloud vast
    echo ""
    echo "To get exact cost estimate:"
    echo "  sky launch $task --dryrun"
}

# ==================== MLflow Integration ====================

# Check if MLflow is reachable
mlflow-check() {
    echo "Checking MLflow at $MLFLOW_URI..."
    curl -s "$MLFLOW_URI" > /dev/null && echo "✓ MLflow is reachable" || echo "✗ MLflow is NOT reachable"
}

# List recent MLflow experiments
mlflow-experiments() {
    echo "Recent MLflow experiments:"
    curl -s "$MLFLOW_URI/api/2.0/mlflow/experiments/search" \
        -H "Content-Type: application/json" \
        -d '{"max_results": 10}' | python3 -m json.tool 2>/dev/null || echo "Failed to fetch experiments"
}

# ==================== MinIO Integration ====================

# Check if MinIO is reachable
minio-check() {
    echo "Checking MinIO at $MINIO_URI..."
    curl -s "$MINIO_URI/minio/health/live" > /dev/null && echo "✓ MinIO is reachable" || echo "✗ MinIO is NOT reachable"
}

# List MinIO buckets
minio-ls() {
    echo "MinIO buckets:"
    AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin123 \
        aws --endpoint-url "$MINIO_URI" s3 ls || echo "Failed to list buckets"
}

# ==================== Kubeflow Integration ====================

# Run the hybrid pipeline
kfp-run() {
    echo "Submitting hybrid pipeline to Kubeflow..."
    cd "$SKYPILOT_DIR"
    
    # This would use kfp CLI or kubectl apply
    # For now, show what would happen
    echo "Pipeline steps:"
    echo "  1. Data preparation (k3s CPU)"
    echo "  2. GPU training (SkyPilot → Vast.ai)"
    echo "  3. Model evaluation (k3s CPU)"
    echo "  4. Model deployment (k3s)"
    echo ""
    echo "To execute: kubectl apply -f pipeline.yaml"
}

# ==================== Cost Tracking ====================

# Show current Vast.ai spending
skypilot-costs() {
    echo "=== Current Vast.ai Costs ==="
    sky status --all | grep -E "(CLUSTER|STATUS|RESOURCES|REGION|HOURLY_PRICE)"
    echo ""
    echo "Note: Costs shown are hourly rates. Total = hours_running × hourly_rate"
}

# Auto-shutdown: terminate clusters after N minutes of idle
skypilot-autostop() {
    local cluster="${1:-llm-train}"
    local minutes="${2:-30}"
    echo "Setting autostop for $cluster after $minutes minutes idle..."
    sky autostop "$cluster" -i "$minutes"
}

# ==================== Help ====================

skypilot-help() {
    cat <> 'EOF'
SkyPilot Helper Commands for Hybrid MLOps Lab
=============================================

Quick Commands:
  skypilot-test           - Test GPU connectivity (cheapest, ~$0.01)
  skypilot-train [model] [epochs]  - Run LLM training
  skypilot-status         - Show all cluster status
  skypilot-stop [cluster] - Stop cluster (preserves disk)
  skydown [cluster]       - Terminate cluster (releases GPU)
  skypilot-cost [task]    - Show cost estimate

Integration Checks:
  mlflow-check            - Verify MLflow connectivity
  mlflow-experiments      - List MLflow experiments
  minio-check             - Verify MinIO connectivity
  minio-ls                - List MinIO buckets

Kubeflow:
  kfp-run                 - Show hybrid pipeline steps

Cost Management:
  skypilot-costs          - Show current spending
  skypilot-autostop [c] [m]  - Auto-terminate after idle minutes

EOF
}

echo "SkyPilot helpers loaded. Run 'skypilot-help' for available commands."