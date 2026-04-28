# MLOps Lab - Complete Kubernetes AI/ML Platform

A production-ready MLOps environment running on k3s with Vast.ai GPU offloading for cost-effective training.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         k3s Cluster                                  │
│                                                                      │
│  Development          Tracking          Storage         Pipelines    │
│  ┌──────────┐       ┌──────────┐      ┌────────┐      ┌─────────┐  │
│  │JupyterHub│       │  MLflow  │      │ MinIO  │      │Kubeflow │  │
│  │:30800    │       │:30500    │      │:30901  │      │:8888    │  │
│  └──────────┘       └──────────┘      └────────┘      └─────────┘  │
│       │                  │                │                 │        │
│       └──────────────────┼────────────────┼─────────────────┘        │
│                          ▼                ▼                          │
│              ┌──────────────────────────────────┐                   │
│              │     PostgreSQL (Metadata)        │                   │
│              └──────────────────────────────────┘                   │
│                                                                      │
└──────────────────────────────────┬───────────────────────────────────┘
                                   │ Tailscale VPN
                                   ▼
                        ┌──────────────────────┐
                        │   Vast.ai Instance   │
                        │  (A100/RTX 5090)     │
                        │   GPU Training       │
                        │   $0.02-0.50/hr      │
                        └──────────────────────┘
```

## Deployed Services

| Service | Purpose | Access | Status |
|---------|---------|--------|--------|
| **MLflow** | Experiment tracking | NodePort :30500 | Running |
| **MinIO** | S3-compatible storage | NodePort :30901 | Running |
| **JupyterHub** | Notebooks & development | NodePort :30800 | Running |
| **TensorBoard** | Training visualization | NodePort :30606 | Running |
| **Kubeflow Pipelines** | ML workflows | ClusterIP :8888 | Running |
| **PostgreSQL** | Metadata database | ClusterIP :5432 | Running |

## Quick Start

### Access Services

All services are exposed via NodePort on your k3s node:

```bash
# JupyterHub (Password: mlops123)
curl http://localhost:30800

# MLflow Tracking
curl http://localhost:30500

# MinIO Console (Login: minioadmin / minioadmin123)
curl http://localhost:30901

# TensorBoard
curl http://localhost:30606
```

Or use port-forwarding:
```bash
kubectl port-forward svc/jupyterhub 8000:8000 -n mlops
kubectl port-forward svc/mlflow 5000:5000 -n mlops
kubectl port-forward svc/minio 9001:9001 -n mlops
```

### Run ML Pipeline

The example pipeline fine-tunes DistilBERT on IMDB reviews:

```python
# pipelines/hf_pipeline.py
# 1. Download dataset from HuggingFace
# 2. Fine-tune model with MLflow tracking
# 3. Log metrics and model artifacts
# 4. Generate KServe deployment config

# Compile and run
python mlops-lab/pipelines/hf_pipeline.py
```

### Use Vast.ai GPU

Add annotations to your training pods:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-training
  annotations:
    vast.ai/gpu-name: "RTX 4090"  # or "A100", "RTX 3090"
    vast.ai/max-dph: "0.50"       # max $/hour
    vast.ai/disk-gb: "20"         # disk space
spec:
  nodeName: virtual-vastai
  containers:
  - name: training
    image: your-training-image
    resources:
      limits:
        nvidia.com/gpu: "1"
```

## Configuration

### MinIO Buckets

Default buckets created:
- `mlflow` - MLflow artifacts
- `models` - Model storage
- `datasets` - Dataset cache

### MLflow Integration

```python
import mlflow
import os

os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://minio.mlops:9000"
os.environ["AWS_ACCESS_KEY_ID"] = "minioadmin"
os.environ["AWS_SECRET_ACCESS_KEY"] = "minioadmin123"

mlflow.set_tracking_uri("http://mlflow.mlops:5000")
mlflow.set_experiment("my-experiment")

with mlflow.start_run():
    mlflow.log_param("epochs", 3)
    mlflow.log_metric("accuracy", 0.95)
    mlflow.pytorch.log_model(model, "model")
```

### Kubeflow Pipelines SDK

```python
import kfp

client = kfp.Client(host="http://ml-pipeline.kubeflow:8888")
client.create_run_from_pipeline_func(
    pipeline_func=hf_pipeline,
    arguments={"model_name": "distilbert-base-uncased"}
)
```

## GitOps with Flux (Optional)

```bash
# Install Flux
flux install

# Configure GitOps
kubectl apply -f mlops-lab/flux/gitops.yaml

# Now changes pushed to Git are auto-deployed
```

## Cost Optimization

### Vast.ai Settings

Set in `vastai-kubelet/deploy/deployment.yaml`:
```yaml
- name: MAX_DPH
  value: "0.50"        # Max $0.50/hour
- name: MIN_COMPUTE_CAP
  value: "700"         # Minimum CUDA capability
- name: SEARCH_LIMIT
  value: "10"          # Check 10 cheapest offers
```

### Resource Limits

All services have conservative limits:
- PostgreSQL: 512MB RAM
- MinIO: 1GB RAM
- MLflow: 512MB RAM
- JupyterHub: 1GB RAM
- Kubeflow API: 512MB RAM

## File Structure

```
mlops-lab/
├── base/
│   ├── namespaces.yaml        # mlops, kubeflow, kserve, flux-system
│   ├── pvcs.yaml              # Persistent volumes
│   ├── postgres.yaml          # Metadata database
│   ├── minio.yaml             # S3-compatible storage
│   ├── mlflow.yaml            # Experiment tracking
│   ├── jupyterhub.yaml        # Notebooks
│   ├── kubeflow-pipelines.yaml # ML workflows
│   ├── mysql-kubeflow.yaml    # Pipeline metadata
│   ├── ingress.yaml           # NodePort services
│   └── optional-tools.yaml    # TensorBoard, W&B
├── pipelines/
│   └── hf_pipeline.py         # HuggingFace text classification
├── flux/
│   └── gitops.yaml            # GitOps configuration
└── README.md                  # This file
```

## Troubleshooting

### Pod stuck in Pending on virtual-vastai

Check Vast.ai controller:
```bash
kubectl logs -n vastai-system deployment/vastai-kubelet
```

### MLflow can't connect to MinIO

Verify MinIO is running:
```bash
kubectl get pods -n mlops -l app=minio
kubectl logs -n mlops job/minio-setup
```

### Kubeflow API not responding

Check MySQL connection:
```bash
kubectl logs -n kubeflow deployment/kubeflow-pipelines-api
kubectl get pods -n kubeflow -l app=mysql
```

### Out of Memory

Services have conservative limits. Increase if needed:
```yaml
resources:
  limits:
    memory: "2Gi"  # Increase from 512Mi
```

## Cleanup

```bash
# Remove MLOps lab
kubectl delete -k mlops-lab/base/
kubectl delete ns kubeflow kserve flux-system

# Keep Vast.ai controller
# kubectl delete -f vastai-kubelet/deploy/
```

## Next Steps

1. **Try the pipeline**: `python mlops-lab/pipelines/hf_pipeline.py`
2. **Deploy KServe**: Uncomment KServe sections for model serving
3. **Add W&B**: Enable Weights & Biases tracking
4. **Configure Flux**: Set up GitOps for auto-deployment
5. **Custom pipelines**: Build your own HuggingFace pipelines

## Architecture Decisions

- **Lightweight**: Kubeflow Pipelines standalone instead of full Kubeflow (~2GB vs ~16GB)
- **Local-first**: All services run on k3s, only GPU training offloaded
- **Cost-effective**: Vast.ai auto-selects cheapest GPU, retry logic for unavailable offers
- **Modular**: Each component can be enabled/disabled independently
- **GitOps-ready**: Flux configuration included for CI/CD

## Status

- [x] PostgreSQL - Running
- [x] MinIO - Running
- [x] MLflow - Running
- [x] JupyterHub - Running
- [x] Kubeflow Pipelines - Running
- [x] TensorBoard - Running
- [x] Vast.ai Integration - Working
- [ ] KServe - Skipped (complex, add later)
- [ ] Flux GitOps - Configured, install flux to enable
- [ ] Weights & Biases - Configured, uncomment to enable