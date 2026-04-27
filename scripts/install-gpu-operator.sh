#!/usr/bin/env bash
# install-gpu-operator.sh
# Install NVIDIA GPU Operator on the k3s cluster

set -euo pipefail

# Check prerequisites
if ! command -v helm &>/dev/null; then
  echo "ERROR: helm is required but not installed."
  echo "Install it from https://helm.sh/docs/intro/install/"
  exit 1
fi

echo "Installing NVIDIA GPU Operator..."

helm repo add nvidia https://helm.ngc.io/nvidia
helm repo update

helm upgrade --install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=true \
  --set toolkit.enabled=true \
  --set devicePlugin.enabled=true \
  --set dcgm.enabled=true

echo ""
echo "Waiting for GPU Operator pods to be ready..."
# Wait for device plugin daemonset to be ready
kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n gpu-operator --timeout=180s || true

echo ""
echo "GPU Operator installed. Check GPU nodes:"
if command -v jq &>/dev/null; then
  kubectl get nodes -o json | jq '.items[].status.capacity | with_entries(select(.key | contains("nvidia")))'
else
  kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.capacity."nvidia.com/gpu"
fi
