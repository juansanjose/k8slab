# MLOps Lab - Cloud-Native Hybrid Setup

Fully automated, containerized MLOps lab that runs locally on Kubernetes (k3s) and offloads GPU training to cloud instances via SkyPilot.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    LOCAL (k3s)                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ MLflow   │  │ MinIO    │  │ PostgreSQL│  │ JupyterHub│   │
│  │ :30500   │  │ :30900   │  │ :5432     │  │ :30800    │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│       │              │              │              │         │
│  └──────────────────────────────────────────────────────┘   │
│                    Kubernetes Cluster                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ SSH Tunnel (automated)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 CLOUD (SkyPilot + RunPod)                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  GPU Instance (NVIDIA L4 - $0.39/hr)               │   │
│  │  ┌──────────────────────────────────────────────┐  │   │
│  │  │ Training Container                             │  │   │
│  │  │  - PyTorch 2.3.0                               │  │   │
│  │  │  - Transformers 4.45.0                         │  │   │
│  │  │  - LoRA Fine-tuning                            │  │   │
│  │  │  - MLflow Logging                              │  │   │
│  │  └──────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Option 1: One-Command Setup (Recommended)

```bash
cd mlops-lab
sudo make setup
```

This will:
1. Install k3s (lightweight Kubernetes)
2. Deploy MLflow, MinIO, PostgreSQL
3. Install SkyPilot
4. Configure everything automatically

### Option 2: Step by Step

```bash
# 1. Setup infrastructure
sudo ./scripts/setup.sh

# 2. Build training container
make build

# 3. Deploy Kubernetes resources
make deploy

# 4. Start training
make train
```

## Usage

### Training Jobs

```bash
# Submit LLM fine-tuning job
make train

# Submit BERT classification job
make train-bert

# Run GPU connectivity test
make test-gpu
```

### Monitoring

```bash
# Check cluster status
make status

# View training logs
make logs

# Open MLflow UI
make mlflow
```

### Local Development (No Cloud)

```bash
# Start local services with Docker Compose
make local-dev

# Access:
#   MLflow: http://localhost:30500
#   MinIO:  http://localhost:30901

# Stop local services
make stop-local
```

## Project Structure

```
mlops-lab/
├── Dockerfile                    # Training container
├── docker-compose.yaml           # Local development stack
├── Makefile                      # Easy commands
├── scripts/
│   ├── setup.sh                 # Automated setup
│   ├── train.sh                 # Submit training jobs
│   ├── cloud-native.sh          # Container orchestration
│   └── skypilot-helpers.sh      # SkyPilot utilities
├── k8s/
│   ├── configs.yaml             # ConfigMaps and Secrets
│   └── training-job.yaml        # Kubernetes Job template
├── skypilot/
│   └── tasks/                   # SkyPilot task definitions
├── training-scripts/
│   ├── train_llm.py             # LLM training code
│   └── train_bert.py            # BERT training code
└── base/                        # Kubernetes base manifests
```

## Configuration

Edit `.env` to configure:
- RunPod API key
- Model selection
- Training hyperparameters
- GPU type

```bash
# Example .env
RUNPOD_API_KEY=your_key_here
MODEL_NAME=TinyLlama/TinyLlama-1.1B-Chat-v1.0
NUM_EPOCHS=1
BATCH_SIZE=2
LEARNING_RATE=2e-4
```

## Cost Optimization

- GPU instances auto-terminate after training
- Local services run on existing hardware (free)
- L4 GPU costs ~$0.39/hr on RunPod
- Typical training run: 2-5 minutes (~$0.03)

## Troubleshooting

### k3s not accessible
```bash
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### SSH tunnel issues
```bash
# Start tunnel manually
ssh -N -R 30500:localhost:30500 -R 30900:localhost:30900 gpu-training
```

### SkyPod not available
RunPod instances have limited availability. The system will automatically try multiple regions.

## Enterprise Features

- **Containerized**: All training runs in Docker containers
- **Kubernetes-native**: Uses K8s Jobs, ConfigMaps, Secrets
- **Automated**: One-command setup and deployment
- **Cloud-agnostic**: SkyPilot supports AWS, GCP, Azure, RunPod, Vast.ai
- **Centralized logging**: All metrics flow to local MLflow
- **Reproducible**: Full experiment tracking with artifacts
- **Cost-effective**: Only pay for GPU time, not idle resources

## Architecture Details

### Container Abstraction
The training environment is fully containerized:
- Base image: `pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime`
- All dependencies baked into image
- No runtime pip installs
- Consistent environment across local and cloud

### Kubernetes Integration
- **ConfigMaps**: Store training hyperparameters
- **Secrets**: Secure API keys and credentials
- **Jobs**: Run training as Kubernetes Jobs
- **PVCs**: Persistent storage for models

### Cloud Bridge
- SSH tunnel connects cloud instances to local services
- SkyPilot manages GPU provisioning
- Automatic cleanup of cloud resources

## Advanced Usage

### Custom Training Task
```bash
# Create custom SkyPilot task
cat > my-task.yaml <<EOF
resources:
  cloud: runpod
  accelerators: A100:1  # Use A100 for larger models
  disk_size: 200

run: |
  python3 /workspace/train_custom.py
EOF

# Submit
make run-custom TASK=my-task.yaml CLUSTER=my-experiment
```

### Multi-GPU Training
```yaml
resources:
  cloud: runpod
  accelerators: L4:4  # 4x L4 GPUs
```

### Custom Container
```dockerfile
FROM localhost:5000/mlops-training:latest
COPY my-training-code.py /workspace/
RUN pip install my-custom-package
```

## Security Notes

- API keys stored in Kubernetes Secrets
- SSH keys managed by SkyPilot automatically
- Local services not exposed to internet (localhost only)
- Tailscale VPN optional for remote access

## Next Steps

1. **Monitor training**: http://localhost:30500
2. **Download models**: `scp -r gpu-training:/workspace/models ./`
3. **Deploy model**: Use KServe or custom inference service
4. **Scale up**: Modify task YAML for multi-GPU or larger instances

## Support

- SkyPilot docs: https://skypilot.readthedocs.io
- RunPod docs: https://docs.runpod.io
- MLflow docs: https://mlflow.org/docs/latest/index.html
