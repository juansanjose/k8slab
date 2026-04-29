# SkyPilot + Kubernetes MLOps Architecture

## Overview

This architecture uses **SkyPilot** as the compute orchestrator while keeping all MLOps services on **Kubernetes**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Kubernetes (k3s)                             │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Control / Metadata Plane                     │  │
│  │  ┌──────────┐  ┌──────────┐  ┌────────┐  ┌──────────────┐   │  │
│  │  │ Kubeflow │  │  MLflow  │  │ MinIO  │  │ PostgreSQL   │   │  │
│  │  │Pipelines │  │Tracking  │  │Storage │  │  Metadata    │   │  │
│  │  └────┬─────┘  └────┬─────┘  └───┬────┘  └──────┬───────┘   │  │
│  │       └─────────────┼────────────┼──────────────┘           │  │
│  │                     │            │                           │  │
│  └─────────────────────┼────────────┼───────────────────────────┘  │
│                        │            │                              │
│  ┌─────────────────────┼────────────┼───────────────────────────┐  │
│  │                     ▼            ▼                           │  │
│  │              ┌────────────────────────┐                      │  │
│  │              │   SkyPilot Controller   │                      │  │
│  │              │   (Runs in k3s Pod)     │                      │  │
│  │              └───────────┬────────────┘                      │  │
│  │                          │                                   │  │
│  └──────────────────────────┼───────────────────────────────────┘  │
└─────────────────────────────┼───────────────────────────────────────┘
                              │
                              │ Vast.ai SDK (proper GPU injection)
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Vast.ai Cloud                                │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Compute Plane (GPU)                        │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐  │  │
│  │  │ GPU Instance 1  │  │ GPU Instance 2  │  │ GPU Inst 3   │  │  │
│  │  │ (RTX 4090)      │  │ (A100)          │  │ (RTX 3090)   │  │  │
│  │  │ Training Job 1  │  │ Training Job 2  │  │ Inference    │  │  │
│  │  └─────────────────┘  └─────────────────┘  └──────────────┘  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## How It Works

### 1. MLOps Services on Kubernetes

All your infrastructure services run on your local k3s cluster:

| Service | Purpose | URL |
|---------|---------|-----|
| **Kubeflow Pipelines** | Orchestration | http://localhost:8888 |
| **MLflow** | Experiment Tracking | http://localhost:30500 |
| **MinIO** | Artifact Storage | http://localhost:30901 |
| **PostgreSQL** | Metadata DB | Cluster internal |
| **JupyterHub** | Notebooks | http://localhost:30800 |

### 2. SkyPilot Controller in Kubernetes

SkyPilot runs as a pod in your cluster:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: skypilot-controller
  namespace: mlops
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: skypilot
        image: berkeleyskypilot/skypilot:latest
        env:
        - name: VASTAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: vastai-credentials
              key: api-key
        - name: KUBECONFIG
          value: /etc/kube/config
        volumeMounts:
        - name: kubeconfig
          mountPath: /etc/kube
```

### 3. GPU Compute via SkyPilot → Vast.ai

When you submit a training job:

```bash
# SkyPilot task definition
sky launch train.yaml --cloud vast --gpus RTX4090
```

What happens:
1. **SkyPilot** analyzes task requirements
2. **Searches** Vast.ai for cheapest GPU matching specs
3. **Creates** GPU instance using Vast.ai SDK (proper GPU injection)
4. **Mounts** MinIO bucket for data access
5. **Runs** training job
6. **Syncs** results back to MLflow/MinIO
7. **Destroys** instance when done

## Task Definition Example

```yaml
# train_llm.yaml
task:
  name: llm-finetuning
  
  resources:
    cloud: vast  # Use Vast.ai for GPU
    accelerators: RTX4090:1
    disk_size: 50
  
  # Mount MinIO for data/model access
  file_mounts:
    /data:
      source: s3://mlops-bucket/datasets
      mode: MOUNT
    /models:
      source: s3://mlops-bucket/models
      mode: MOUNT
  
  setup: |
    # Install dependencies
    pip install transformers datasets accelerate peft mlflow
    
    # Configure MLflow to use local server
    export MLFLOW_TRACKING_URI=http://100.87.186.22:30500
    
  run: |
    # Your training script
    python /workspace/train.py \
      --model TinyLlama/TinyLlama-1.1B-Chat-v1.0 \
      --dataset tatsu-lab/alpaca \
      --output /models/tinyllama-finetuned
```

## Key Integration Points

### MLflow Integration

```python
# Inside SkyPilot task (running on Vast.ai GPU)
import mlflow

# Connect back to your local MLflow (via Tailscale or public endpoint)
mlflow.set_tracking_uri("http://100.87.186.22:30500")
mlflow.set_experiment("llm-experiments")

with mlflow.start_run():
    mlflow.log_param("model", "TinyLlama")
    mlflow.log_metric("accuracy", 0.95)
    # Model artifacts saved to MinIO automatically
```

### MinIO Integration

```yaml
# SkyPilot task with MinIO storage
file_mounts:
  /workspace/data:
    source: s3://datasets
    store: minio
    endpoint_url: http://100.87.186.22:30900
    access_key: minioadmin
    secret_key: minioadmin123
```

### Kubeflow Integration

```python
# Kubeflow pipeline step that calls SkyPilot
@dsl.component

def train_on_gpu(
    model_name: str,
    dataset: str
) -> str:
    import subprocess
    
    # Generate SkyPilot task
    task_yaml = f"""
task:
  name: kfp-gpu-training
  resources:
    cloud: vast
    accelerators: RTX4090:1
  run: |
    pip install transformers datasets
    python train.py --model {model_name} --dataset {dataset}
"""
    
    # Submit via SkyPilot
    subprocess.run(["sky", "launch", "-c", "kfp-run", "--yaml", "-"], 
                   input=task_yaml, text=True, check=True)
    
    return "Training completed"
```

## Architecture Benefits

### Control Plane (Kubernetes)
- **Persistent**: Services stay running on your laptop
- **Free**: No cost for MLflow, MinIO, PostgreSQL
- **Local**: Fast access for development
- **Reliable**: Not affected by GPU instance lifecycle

### Compute Plane (SkyPilot + Vast.ai)
- **Cheap**: $0.02-0.50/hr for GPUs
- **Elastic**: Scale up/down automatically
- **Proper GPU injection**: Via Vast.ai SDK (no CDI issues)
- **Multi-cloud**: Can burst to RunPod, Lambda, etc.

### Integration
- **Data flow**: MinIO buckets mounted on GPU instances
- **Metrics flow**: MLflow tracking from GPU instances
- **Orchestration**: Kubeflow pipelines trigger SkyPilot tasks
- **Cost control**: Only pay for GPU time used

## Deployment Steps

### 1. Deploy MLOps Services (Already Done)

```bash
# Your k3s cluster already has:
kubectl apply -k mlops-lab/base/
```

### 2. Configure SkyPilot

```bash
# Set Vast.ai credentials
mkdir -p ~/.config/vastai
echo "your-api-key" > ~/.config/vastai/vast_api_key

# Set KUBECONFIG for SkyPilot
export KUBECONFIG=~/.kube/config

# Verify
sky check
```

### 3. Submit Training Jobs

```bash
# Run training on Vast.ai GPU
sky launch train_llm.yaml --cloud vast --gpus RTX4090

# Or use Kubernetes backend for local testing
sky launch train_llm.yaml --cloud kubernetes --gpus 0
```

### 4. Monitor Results

```bash
# Check MLflow UI
http://localhost:30500

# Check MinIO console
http://localhost:30901

# Check SkyPilot status
sky status
sky logs kfp-run
```

## Cost Model

| Component | Cost | Notes |
|-----------|------|-------|
| **k3s cluster** (laptop) | $0 | Your hardware |
| **MLflow** | $0 | Runs locally |
| **MinIO** | $0 | Runs locally |
| **PostgreSQL** | $0 | Runs locally |
| **GPU via SkyPilot** | $0.02-0.50/hr | Only when training |
| **Total per run** | ~$0.15-1.00 | 30min-2hr training |

## Comparison

| Approach | Cost | Complexity | GPU Access | Integration |
|----------|------|------------|------------|-------------|
| Pure k3s (no GPU) | Free | Low | ❌ None | ✅ Full |
| Virtual Kubelet | Cheap | High | ❌ Broken | ❌ None |
| Real Nodes + Tailscale | Cheap | Very High | ⚠️ CDI Bug | ✅ Full |
| **SkyPilot + k3s** | Cheap | Medium | ✅ Works | ✅ Full |
| Cloud k8s (EKS/GKE) | Expensive | Low | ✅ Yes | ✅ Full |

## Files Created

```
mlops-lab/
├── skypilot/
│   ├── train_llm.yaml          # SkyPilot task definition
│   ├── infer_llm.yaml          # Inference task
│   ├── pipeline.yaml           # Kubeflow + SkyPilot integration
│   └── README.md               # This file
└── ...
```

## Next Steps

1. **Test SkyPilot**: `sky launch --cloud vast --gpus RTX4090 echo.yaml`
2. **Create task files**: Define your training/inference tasks
3. **Integrate with Kubeflow**: Add SkyPilot steps to pipelines
4. **Monitor costs**: Use `sky status` to track spending

## Troubleshooting

### SkyPilot can't find Vast.ai

```bash
# Check credentials
sky check vast

# Verify API key
cat ~/.config/vastai/vast_api_key
```

### Kubernetes backend not working

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/config
sky check kubernetes
```

### MLflow not reachable from GPU instance

```bash
# Ensure MLflow is accessible via public IP or Tailscale
# In task YAML:
env:
  MLFLOW_TRACKING_URI: http://your-public-ip:30500
```

## Summary

This architecture gives you:
- ✅ **Free MLOps infrastructure** on your laptop
- ✅ **Cheap GPU compute** via Vast.ai
- ✅ **Proper GPU injection** (via Vast.ai SDK)
- ✅ **Full integration** between control and compute planes
- ✅ **Multi-cloud failover** (can use RunPod, Lambda, etc.)
- ✅ **Production-ready** tooling (SkyPilot is battle-tested)

**This is the right way to build a hybrid MLOps lab!**