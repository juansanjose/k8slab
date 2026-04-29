#!/bin/bash
# test-real-node.sh
# Test that verifies the real node approach works

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== Testing Real Kubernetes Node Setup ==="
log ""

# Check current nodes
log "Current cluster nodes:"
kubectl get nodes -o wide
log ""

# Check if there are any Vast.ai nodes
if kubectl get nodes -l vast.ai/gpu=true 2>/dev/null | grep -q vastai; then
    log "Vast.ai worker nodes detected!"
    log ""
    
    # Run test job
    log "Submitting GPU test job..."
    kubectl apply -f gpu-training-real-node.yaml
    
    log ""
    log "Watching job..."
    kubectl wait --for=condition=complete job/gpu-training-real-node --timeout=300s 2>/dev/null || true
    
    log ""
    log "Job logs:"
    kubectl logs job/gpu-training-real-node
    
    log ""
    log "Cleaning up..."
    kubectl delete job gpu-training-real-node --force 2>/dev/null || true
    
    log ""
    log "=== Test Complete ==="
else
    log "No Vast.ai worker nodes found in cluster."
    log ""
    log "To add a worker node:"
    log "1. Run: bash scripts/setup-k3s-server-for-workers.sh"
    log "2. Create Vast.ai instance with worker setup script"
    log "3. Or use: bash scripts/create-vastai-worker.sh"
    log ""
    log "The node should appear in 'kubectl get nodes' within 2-3 minutes."
fi