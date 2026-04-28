# LLM Training Workflow on Vast.ai

## Complete Example: Fine-tune TinyLlama

This guide walks through training an LLM on Vast.ai GPU using Kubernetes.

## Prerequisites

1. Vast.ai controller is running
2. Virtual node `virtual-vastai` is Ready
3. You have a Vast.ai API key configured

## Step-by-Step Workflow

### Step 1: Understand What Happens

When you submit a Job with `nodeName: virtual-vastai`:

1. **Kubernetes** schedules the pod to `virtual-vastai` node
2. **VastAI Controller** sees the pod and searches for cheapest GPU
3. **VastAI API** creates a Docker container with GPU in their datacenter
4. **Container** runs your training script
5. **Container stops** when training is done
6. **Controller** destroys the Vast.ai instance

### Step 2: Quick Test (5 minutes, ~$0.10)

```bash
cd mlops-lab/examples

# Submit quick test job
kubectl apply -f quick-test.yaml

# Watch logs
kubectl logs -f job/quick-llm-test

# Or use the helper script
./quick-test.sh
```

**What it does:**
- Provisions RTX 4090 on Vast.ai
- Downloads TinyLlama model
- Runs inference test
- Shows GPU info
- Cost: ~$0.10 (5 min × $0.30/hr)

### Step 3: Full Training (30-60 minutes, ~$0.25-0.50)

```bash
# Submit training job
kubectl apply -f tinyllama-training.yaml

# Watch instance creation
kubectl logs -n vastai-system deployment/vastai-kubelet -f

# Monitor training
kubectl logs -f job/llm-training-tinyllama

# Check status
kubectl get job llm-training-tinyllama
kubectl get pods -o wide | grep llm-training
```

**What it does:**
- Downloads TinyLlama (1.1B parameters)
- Downloads Alpaca dataset (1000 samples)
- Applies LoRA (only 0.5% of parameters trained)
- Fine-tunes for 1 epoch
- Saves model to `/workspace/output`

### Step 4: Get Your Model

Since containers are isolated, you need to get the model out:

**Option A: Push to HuggingFace Hub (Recommended)**

```bash
# Create HF token secret
kubectl create secret generic hf-token \
  --from-literal=token=hf_xxxxxxxxxxxxx

# Uncomment in tinyllama-training.yaml:
# - name: HF_TOKEN
#   valueFrom:
#     secretKeyRef:
#       name: hf-token
#       key: token
# - name: PUSH_TO_HUB
#   value: "true"
# - name: HF_REPO_ID
#   value: "your-username/tinyllama-alpaca"

# Re-apply
kubectl apply -f tinyllama-training.yaml
```

**Option B: SCP from Vast.ai Instance**

```bash
# Get instance details from Vast.ai web UI
# SSH into instance and copy files
# (You need to keep the instance running to do this)
```

**Option C: Use Custom Image with Persistent Storage**

Build an image that uploads to S3/GCS:
```dockerfile
# In your Dockerfile
RUN pip install awscli
# In training script
# aws s3 cp /workspace/output s3://your-bucket/
```

### Step 5: Custom Training Script

Create your own `train_llm.py`:

```python
import os
from transformers import AutoModelForCausalLM, AutoTokenizer, Trainer
from peft import LoraConfig, get_peft_model

# Load model
model = AutoModelForCausalLM.from_pretrained(
    os.getenv("MODEL_NAME"),
    device_map="auto"
)

# Apply LoRA
model = get_peft_model(model, LoraConfig(r=16, lora_alpha=32))

# Train...
# Save...
```

Build and push:
```bash
cd mlops-lab/training-scripts
docker build -t localhost:5000/my-llm-trainer:latest .
docker push localhost:5000/my-llm-trainer:latest
```

Use in job:
```yaml
containers:
- name: training
  image: localhost:5000/my-llm-trainer:latest
```

## Cost Breakdown

| Step | Time | GPU | Cost |
|------|------|-----|------|
| Quick Test | 5 min | RTX 4090 @ $0.30/hr | $0.03 |
| TinyLlama Training | 30 min | RTX 4090 @ $0.30/hr | $0.15 |
| Llama-2-7B Training | 2 hours | A100 @ $0.50/hr | $1.00 |
| Mistral-7B Training | 3 hours | RTX 4090 @ $0.40/hr | $1.20 |

## Monitoring

### Check Vast.ai Instance

```bash
# List your instances
curl -s -H "Authorization: Bearer $VASTAI_KEY" \
  https://console.vast.ai/api/v0/instances/ | \
  jq '.instances[] | {id, status, gpu_name, dph_total, actual_status}'
```

### Check Kubernetes

```bash
# Watch pod events
kubectl get events --field-selector involvedObject.name=llm-training-tinyllama

# Check pod status
kubectl get pod -o wide | grep llm-training

# View logs
kubectl logs job/llm-training-tinyllama

# Check controller logs
kubectl logs -n vastai-system deployment/vastai-kubelet
```

## Troubleshooting

### Pod stuck in Pending

```bash
# Check if instance was created
kubectl logs -n vastai-system deployment/vastai-kubelet | grep "Created instance"

# Check Vast.ai for the instance
curl -s -H "Authorization: Bearer $VASTAI_KEY" \
  https://console.vast.ai/api/v0/instances/
```

### Out of GPU Memory

Use smaller model or quantization:
```python
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    load_in_8bit=True,  # or load_in_4bit=True
    device_map="auto"
)
```

### Model download fails

Check internet in container:
```bash
kubectl exec -it job/llm-training-tinyllama -- curl -I https://huggingface.co
```

### Training too slow

- Use smaller model (TinyLlama vs Llama-2)
- Increase batch size (if GPU memory allows)
- Use gradient accumulation
- Reduce sequence length (MAX_LENGTH)

## Next Steps

1. **Try quick test**: `kubectl apply -f quick-test.yaml`
2. **Run training**: `kubectl apply -f tinyllama-training.yaml`
3. **Build custom image**: Modify Dockerfile for your needs
4. **Create pipeline**: Use Kubeflow Pipelines to automate
5. **Scale up**: Try larger models (Llama-2-7B, Mistral-7B)

## Files

```
mlops-lab/
├── training-scripts/
│   ├── train_llm.py          # Main training script
│   ├── Dockerfile            # Custom training image
│   └── LLM_TRAINING_GUIDE.md # Full guide
└── examples/
    ├── quick-test.yaml        # 5-minute test
    ├── quick-test.sh          # Helper script
    └── tinyllama-training.yaml # Full training job
```