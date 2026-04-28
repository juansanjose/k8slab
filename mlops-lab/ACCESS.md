# Accessing Your MLOps Lab

## Service URLs

All services are exposed on NodePorts. Access them at:

| Service | URL | Credentials |
|---------|-----|-------------|
| JupyterHub | http://localhost:30800 | admin / mlops123 |
| MLflow | http://localhost:30500 | None |
| MinIO Console | http://localhost:30901 | minioadmin / minioadmin123 |
| TensorBoard | http://localhost:30606 | None |

## Quick Tests

### Test MLflow
```bash
curl http://localhost:30500/api/2.0/mlflow/experiments/list
```

### Test MinIO
```bash
mc alias set local http://localhost:30900 minioadmin minioadmin123
mc ls local
```

### Run GPU Training
```bash
kubectl apply -f examples/gpu-training.yaml
kubectl get pod gpu-training -o wide
```

## What's Deployed

**Core Infrastructure (mlops namespace):**
- PostgreSQL - Metadata database
- MinIO - S3-compatible storage (buckets: mlflow, models, datasets)
- MLflow - Experiment tracking with MinIO artifact store
- JupyterHub - Notebooks with DummyAuthenticator
- TensorBoard - Training visualization

**ML Pipelines (kubeflow namespace):**
- Kubeflow Pipelines API - Workflow orchestration
- MySQL - Pipeline metadata

**GPU Offloading (vastai-system namespace):**
- Vast.ai Virtual Kubelet - Auto GPU instance provisioning
- Virtual Node - virtual-vastai

## File Structure

```
mlops-lab/
├── base/                        # Kubernetes manifests
│   ├── namespaces.yaml          # mlops, kubeflow, kserve
│   ├── pvcs.yaml               # Persistent volumes
│   ├── postgres.yaml           # Database
│   ├── minio.yaml              # Object storage
│   ├── mlflow.yaml             # Experiment tracking
│   ├── jupyterhub.yaml         # Notebooks
│   ├── kubeflow-pipelines.yaml # ML pipelines
│   ├── mysql-kubeflow.yaml     # Pipeline metadata
│   ├── ingress.yaml            # NodePort services
│   └── optional-tools.yaml     # TensorBoard
├── pipelines/
│   └── hf_pipeline.py          # HuggingFace text classification
├── flux/
│   └── gitops.yaml             # GitOps configuration
└── README.md                   # Full documentation
```

## Next Steps

1. **Try JupyterHub**: http://localhost:30800 (admin/mlops123)
2. **Explore MLflow**: http://localhost:30500
3. **Run the pipeline**: `python mlops-lab/pipelines/hf_pipeline.py`
4. **GPU training**: Apply pods with `nodeName: virtual-vastai`
5. **GitOps**: Install Flux and apply `mlops-lab/flux/gitops.yaml`

## Architecture

```
Local k3s Cluster                    Vast.ai Cloud
┌─────────────────────────┐          ┌──────────────┐
│ JupyterHub              │          │  GPU Instance │
│ MLflow                  │          │  (A100/RTX)   │
│ MinIO ──┐               │          │  $0.02-0.50/hr│
│ PostgreSQL│             │◄────────►│              │
│ Kubeflow  │             │  VPN     │              │
└─────────────────────────┘          └──────────────┘
```