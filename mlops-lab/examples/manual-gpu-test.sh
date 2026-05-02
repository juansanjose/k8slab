#!/bin/bash
# Manual GPU test using Vast.ai CLI

echo "=== Manual GPU Test ==="

# Search for cheapest RTX 4090
echo "Searching for GPU..."
OFFERS=$(vastai search offers 'gpu_name=="RTX 4090"' -o dph --raw)
OFFER_ID=$(echo "$OFFERS" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['ask_contract_id'])" 2>/dev/null)

if [ -z "$OFFER_ID" ]; then
    echo "No offers found"
    exit 1
fi

echo "Found offer: $OFFER_ID"

# Create instance
echo "Creating instance..."
RESULT=$(vastai create instance $OFFER_ID --image pytorch/pytorch:latest --disk 10 --ssh --raw)
INSTANCE_ID=$(echo "$RESULT" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data['new_contract'])" 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
    echo "Failed to create instance"
    echo "$RESULT"
    exit 1
fi

echo "Instance ID: $INSTANCE_ID"
echo "Waiting for instance to start (60s)..."
sleep 60

# Get SSH info
echo "Getting SSH info..."
SSH_URL=$(vastai ssh-url $INSTANCE_ID)
echo "SSH URL: $SSH_URL"

# Parse SSH info
SSH_HOST=$(echo "$SSH_URL" | sed 's|ssh://root@||' | sed 's|:.*||')
SSH_PORT=$(echo "$SSH_URL" | sed 's|.*:||')

echo "Host: $SSH_HOST, Port: $SSH_PORT"

# Wait a bit more for SSH
echo "Waiting for SSH (30s)..."
sleep 30

# Test GPU
echo ""
echo "=== Testing GPU ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$SSH_HOST -p $SSH_PORT "nvidia-smi" 2>/dev/null

# Test PyTorch
echo ""
echo "=== Testing PyTorch ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$SSH_HOST -p $SSH_PORT "python3 -c 'import torch; print(f\"PyTorch: {torch.__version__}\"); print(f\"CUDA: {torch.cuda.is_available()}\"); print(f\"GPU: {torch.cuda.get_device_name(0)}\")'" 2>/dev/null

# Test connectivity to local services
echo ""
echo "=== Testing Local Services ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@$SSH_HOST -p $SSH_PORT "curl -s --max-time 3 http://100.87.186.22:30500 >/dev/null && echo 'MLflow: OK' || echo 'MLflow: FAIL'" 2>/dev/null
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@$SSH_HOST -p $SSH_PORT "curl -s --max-time 3 http://100.87.186.22:30900/minio/health/live >/dev/null && echo 'MinIO: OK' || echo 'MinIO: FAIL'" 2>/dev/null

# Destroy
echo ""
echo "=== Cleaning Up ==="
echo "y" | vastai destroy instance $INSTANCE_ID

echo ""
echo "=== Test Complete ==="