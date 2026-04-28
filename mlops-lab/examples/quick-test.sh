#!/bin/bash
# quick-llm-test.sh
# Quick script to test LLM training on Vast.ai

echo "=========================================="
echo "Quick LLM Training Test"
echo "=========================================="
echo ""

# 1. Submit job
echo "[1/4] Submitting test job to Vast.ai..."
kubectl apply -f quick-test.yaml
echo ""

# 2. Watch instance creation
echo "[2/4] Watching instance creation..."
echo "Press Ctrl+C when you see 'Created instance' in the logs"
echo ""
sleep 5
kubectl logs -n vastai-system deployment/vastai-kubelet -f &
KUBELET_PID=$!
sleep 10
kill $KUBELET_PID 2>/dev/null

# 3. Wait for pod to start
echo ""
echo "[3/4] Waiting for pod to start..."
kubectl wait --for=condition=Ready pod -l job-name=quick-llm-test --timeout=300s 2>/dev/null || true

# 4. Watch training logs
echo ""
echo "[4/4] Watching training logs..."
echo "Press Ctrl+C to stop watching"
echo ""
kubectl logs -f job/quick-llm-test

echo ""
echo "=========================================="
echo "Test complete!"
echo ""
echo "To check status:"
echo "  kubectl get job quick-llm-test"
echo ""
echo "To see results:"
echo "  kubectl logs job/quick-llm-test"
echo ""
echo "To clean up:"
echo "  kubectl delete job quick-llm-test"
echo "=========================================="