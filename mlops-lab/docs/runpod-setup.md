# RunPod Setup Guide

## Overview

RunPod is the **recommended GPU backend** for this hybrid MLOps lab. It integrates seamlessly with SkyPilot and is more reliable than Vast.ai (which has SDK compatibility issues requiring PR fixes).

## Pricing

| GPU | RunPod Price/hr | Vast.ai Price/hr |
|-----|----------------|------------------|
| RTX 4090 | ~$0.44 | ~$0.25-0.40 |
| RTX 3090 | ~$0.25 | ~$0.15-0.30 |
| A100 40GB | ~$1.99 | ~$1.00-2.00 |
| A100 80GB | ~$2.49 | ~$1.50-2.50 |

**Trade-off:** RunPod is slightly more expensive but:
- Works out-of-the-box with SkyPilot
- More reliable infrastructure
- Better network connectivity
- No SDK compatibility issues

## Setup

### 1. Get RunPod API Key

1. Sign up at https://www.runpod.io/
2. Go to Settings → API Keys
3. Generate a new API key
4. Save it to `~/.runpod/api_key`:

```bash
mkdir -p ~/.runpod
echo "your-api-key" > ~/.runpod/api_key
```

Or use the one in your `.env` file:
```bash
mkdir -p ~/.runpod
grep RunPod_Key /home/juan/k8s/.env | cut -d= -f2 > ~/.runpod/api_key
```

### 2. Install SkyPilot with RunPod Support

```bash
pip install -U "skypilot[runpod]"
```

### 3. Verify Configuration

```bash
sky check runpod
```

Should show:
```
RunPod: enabled [compute]
```

## Usage

### Quick Test

```bash
# Test GPU connectivity (~$0.01, 2-5 min)
make gpu-test

# Or directly:
cd mlops-lab/skypilot
sky launch tasks/gpu-test-runpod.yaml -c gpu-test --yes --down
```

### Training Jobs

```bash
# LLM Fine-tuning
make train-llm

# BERT Classification
make train-bert
```

### Manual Commands

```bash
# Launch with custom parameters
sky launch tasks/train-llm-runpod.yaml \
  -c my-training \
  --env NUM_EPOCHS=3 \
  --env MODEL_NAME=meta-llama/Llama-2-7b-hf \
  --yes

# Check status
sky status

# View logs
sky logs my-training

# SSH into instance
ssh my-training

# Stop (preserve disk)
sky stop my-training

# Terminate (delete everything)
sky down my-training
```

## Task Configuration

### Example: GPU Test

```yaml
resources:
  cloud: runpod
  accelerators: RTX4090:1
  disk_size: 10

envs:
  MLFLOW_TRACKING_URI: http://100.87.186.22:30500

run: |
  nvidia-smi
  python3 -c "import torch; print(torch.cuda.is_available())"
```

### Example: LLM Training

```yaml
resources:
  cloud: runpod
  accelerators: RTX4090:1
  disk_size: 50

file_mounts:
  /workspace/data:
    source: s3://datasets
    store: minio
    endpoint_url: http://100.87.186.22:30900
    access_key: minioadmin
    secret_key: minioadmin123
    mode: MOUNT

setup: |
  pip install transformers datasets torch

run: |
  python train.py --model meta-llama/Llama-2-7b-hf
```

## Available GPUs

Check available GPUs:
```bash
sky show-gpus --cloud runpod
```

Common options:
- `RTX4090:1` - Best value for small/medium models
- `A100:1` - Best for large models (70B+)
- `A100:8` - Multi-GPU training

## Network Connectivity

RunPod instances have **outbound internet access**, so they can reach:
- Your MLflow server (via public/Tailscale IP)
- MinIO (via public/Tailscale IP)
- HuggingFace Hub
- GitHub

**No Tailscale required** for basic functionality, but recommended for security.

## Cost Optimization

### Spot Instances

Save up to 50% with spot/preemptible instances:

```yaml
resources:
  cloud: runpod
  accelerators: RTX4090:1
  use_spot: true
```

### Auto-shutdown

```bash
# Auto-terminate after 30 minutes idle
sky autostop my-cluster -i 30

# For one-off jobs
sky launch task.yaml --down
```

### Right-size Your GPU

Choose based on model size:
- **< 1B params**: RTX 3090 ($0.25/hr)
- **1-7B params**: RTX 4090 ($0.44/hr)
- **7-70B params**: A100 40GB ($1.99/hr)
- **> 70B params**: A100 80GB ($2.49/hr)

## Troubleshooting

### "RunPod: disabled"
```bash
# Check API key file
cat ~/.runpod/api_key

# Reinstall
pip install -U "skypilot[runpod]"
```

### "No instances found"
```bash
# Check GPU availability
sky show-gpus --cloud runpod

# Try different GPU
sky launch task.yaml --gpus RTX3090:1
```

### Instance won't start
```bash
# Check RunPod console
# https://www.runpod.io/console/pods

# Try different region (if supported)
```

### Can't reach MLflow
```bash
# Ensure MLflow is accessible from internet
# Or use Tailscale for private networking
curl http://your-public-ip:30500
```

## Migration from Vast.ai

If you were using Vast.ai before:

1. **Install RunPod support**: `pip install -U "skypilot[runpod]"`
2. **Get API key**: From https://www.runpod.io/
3. **Update tasks**: Change `cloud: vast` to `cloud: runpod`
4. **Test**: `make gpu-test`

Vast.ai tasks remain in `tasks/*-vast.yaml` but require PR fixes to work.

## References

- RunPod: https://www.runpod.io/
- SkyPilot RunPod docs: https://docs.skypilot.co/en/latest/getting-started/installation.html#runpod
- RunPod pricing: https://www.runpod.io/pricing

## Next Steps

1. Run `make gpu-test` to verify setup
2. Try `make train-llm` for first training job
3. Set up auto-shutdown for cost control
4. Configure spot instances for savings