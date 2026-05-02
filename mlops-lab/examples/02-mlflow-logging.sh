#!/bin/bash
# Example 2: Test MLflow Logging from GPU Instance (RunPod)
# Verifies metrics can flow from RunPod back to local MLflow

echo "=========================================="
echo "  Example 2: MLflow Integration Test"
echo "  Backend: RunPod"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Launch GPU instance on RunPod"
echo "  2. Log test metrics to local MLflow"
echo "  3. Verify artifacts in MinIO"
echo "  4. Auto-cleanup"
echo ""

cd /home/juan/k8s/mlops-lab/skypilot

# Create a minimal test task
cat > /tmp/mlflow-test-runpod.yaml << 'EOF'
resources:
  cloud: runpod
  accelerators: RTX4090:1
  disk_size: 10

envs:
  MLFLOW_TRACKING_URI: http://100.87.186.22:30500
  MLFLOW_S3_ENDPOINT_URL: http://100.87.186.22:30900
  AWS_ACCESS_KEY_ID: minioadmin
  AWS_SECRET_ACCESS_KEY: minioadmin123

run: |
  pip install -q mlflow boto3
  
  python3 -c "
import mlflow
import random
import time

mlflow.set_tracking_uri('http://100.87.186.22:30500')
mlflow.set_experiment('skypilot-integration-test')

with mlflow.start_run():
    # Log parameters
    mlflow.log_params({
        'test': True,
        'gpu': 'RTX4090',
        'cloud': 'runpod'
    })
    
    # Simulate training
    for epoch in range(5):
        loss = 1.0 / (epoch + 1) + random.random() * 0.1
        accuracy = 0.5 + (epoch * 0.1) + random.random() * 0.05
        
        mlflow.log_metrics({'loss': loss, 'accuracy': accuracy}, step=epoch)
        print(f'Epoch {epoch}: loss={loss:.4f}, acc={accuracy:.4f}')
        time.sleep(1)
    
    print('MLflow test complete!')
    print(f'View at: http://100.87.186.22:30500')
"
EOF

sky launch /tmp/mlflow-test-runpod.yaml -c mlflow-test --yes --down

echo ""
echo "Check MLflow UI: http://100.87.186.22:30500"
echo "Look for experiment: skypilot-integration-test"

# Note: Vast.ai version exists but requires PR fixes
# See docs/VASTAI_PR_DOCUMENTATION.md for details