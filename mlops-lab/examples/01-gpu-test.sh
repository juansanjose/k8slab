#!/bin/bash
# Example 1: Quick GPU Test on RunPod
# Tests GPU connectivity and PyTorch on cheapest available GPU

echo "=========================================="
echo "  Example 1: GPU Connectivity Test"
echo "  Backend: RunPod"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Launch cheapest available GPU on RunPod (~$0.01-0.05)"
echo "  2. Test nvidia-smi, PyTorch CUDA"
echo "  3. Test connectivity to MLflow and MinIO"
echo "  4. Auto-terminate after completion"
echo ""
echo "Starting in 3 seconds..."
sleep 3

cd /home/juan/k8s/mlops-lab/skypilot
sky launch tasks/gpu-test-runpod.yaml -c gpu-test --yes --down

echo ""
echo "Complete! Check SkyPilot status: sky status"

# Note: Vast.ai version exists at tasks/gpu-test.yaml but requires PR fixes
# See docs/VASTAI_PR_DOCUMENTATION.md for details