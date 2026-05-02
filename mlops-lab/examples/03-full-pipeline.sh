#!/bin/bash
# Example 3: Full Training Pipeline on RunPod
# Runs LLM fine-tuning end-to-end with MLflow tracking

echo "=========================================="
echo "  Example 3: Full LLM Training Pipeline"
echo "  Backend: RunPod"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Launch RTX 4090 on RunPod"
echo "  2. Fine-tune TinyLlama with LoRA"
echo "  3. Log metrics to MLflow"
echo "  4. Save model to MinIO"
echo "  5. Cost: ~$0.44/hr for RTX 4090"
echo ""
echo "Starting in 5 seconds (Ctrl+C to cancel)..."
sleep 5

cd /home/juan/k8s/mlops-lab/skypilot

# Launch training task
sky launch tasks/train-llm-runpod.yaml \
  -c llm-training-run \
  --yes \
  --env NUM_EPOCHS=1 \
  --env MODEL_NAME=TinyLlama/TinyLlama-1.1B-Chat-v1.0

echo ""
echo "=========================================="
echo "  Training Complete!"
echo "=========================================="
echo ""
echo "Results:"
echo "  MLflow: http://100.87.186.22:30500"
echo "  MinIO:  http://100.87.186.22:30901"
echo ""
echo "To terminate GPU instance:"
echo "  sky down llm-training-run"
echo ""
echo "To check costs:"
echo "  sky status --all"

# Note: Vast.ai version exists at tasks/train-llm.yaml but requires PR fixes
# See docs/VASTAI_PR_DOCUMENTATION.md for details