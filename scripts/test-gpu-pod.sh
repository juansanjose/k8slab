#!/usr/bin/env bash
# test-gpu-pod.sh
# Deploy a test pod to verify GPU scheduling works

set -euo pipefail

NODE_NAME="${1:-}"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cuda-test
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda
    image: nvidia/cuda:12.4.1-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

if [[ -n "$NODE_NAME" ]]; then
  kubectl patch pod cuda-test --type=merge -p "{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$NODE_NAME\"}}}"
fi

echo "Pod created. Waiting for completion..."
# Wait for pod to be Ready or Succeeded (for one-shot jobs)
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/cuda-test --timeout=120s 2>/dev/null || \
kubectl wait --for=condition=Ready pod/cuda-test --timeout=120s 2>/dev/null || true

echo ""
echo "Pod status:"
kubectl get pod cuda-test -o wide

echo ""
echo "Pod logs:"
kubectl logs cuda-test || true

echo ""
echo "Cleaning up..."
kubectl delete pod cuda-test --ignore-not-found
