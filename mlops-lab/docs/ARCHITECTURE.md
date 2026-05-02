# Architecture Details

## Hybrid MLOps Architecture

### Design Principles

1. **Control Plane on Kubernetes**: Persistent, free, local services
2. **Compute Plane via SkyPilot**: Elastic, cheap GPU on demand
3. **Proper GPU Injection**: Uses Vast.ai SDK (avoids CDI bugs)
4. **Full Integration**: Metrics, models, and data flow seamlessly

### Component Diagram

```
User (Laptop)
    │
    ├─► kubectl ──► Kubernetes (k3s)
    │                  │
    │                  ├─► MLflow (experiment tracking)
    │                  ├─► MinIO (artifact storage)
    │                  ├─► PostgreSQL (metadata)
    │                  ├─► JupyterHub (development)
    │                  ├─► Kubeflow (pipelines)
    │                  │
    │                  └─► SkyPilot Controller (optional pod)
    │
    └─► sky CLI ──► SkyPilot API Server
                        │
                        ├─► Vast.ai Backend (GPU instances)
                        ├─► Kubernetes Backend (local testing)
                        └─► Other clouds (AWS, GCP, etc.)
```

### Data Flow

**Training Job Flow**:
```
1. User: sky launch train-llm.yaml
   │
2. SkyPilot Controller
   ├─ Analyzes task requirements
   ├─ Checks Vast.ai for cheapest GPU
   └─ Creates instance via SDK
   │
3. Vast.ai GPU Instance
   ├─ Mounts MinIO bucket (datasets)
   ├─ Runs training script
   ├─ Logs metrics → MLflow (HTTP)
   └─ Saves model → MinIO (S3)
   │
4. SkyPilot
   ├─ Monitors job completion
   └─ Auto-terminates instance
   │
5. User
   ├─ Views metrics in MLflow UI
   ├─ Downloads model from MinIO
   └─ Pays only for GPU time used
```

### Why SkyPilot?

**Problem**: Raw Vast.ai REST API has CDI device injection bug
**Solution**: SkyPilot uses official Vast.ai SDK which handles GPU properly

**Additional Benefits**:
- Multi-cloud failover (RunPod, Lambda, AWS, GCP)
- Cost optimization (finds cheapest GPU automatically)
- Spot instance support
- Managed job queue
- Auto-cleanup

### Kubernetes Integration

SkyPilot is **not** a Kubernetes scheduler. It runs alongside Kubernetes:

```
Kubernetes                    SkyPilot
──────────                    ────────
Schedules CPU pods            Provisions GPU instances
Persistent services           Ephemeral compute
Local network                 External cloud
kubectl                       sky CLI

Integration:
- Kubeflow steps call `sky launch`
- Kubernetes Jobs trigger SkyPilot tasks
- Services communicate via HTTP/S3
```

### Network Architecture

```
Vast.ai GPU Instance
    │
    ├─► Internet
    │     │
    │     ├─► MLflow (100.87.186.22:30500)
    │     ├─► MinIO  (100.87.186.22:30900)
    │     └─► k3s API (optional)
    │
    └─► No direct pod networking
        (use service endpoints via public IP)
```

**Note**: GPU instances can't reach Kubernetes pod IPs directly. Use:
- NodePort services with public/Tailscale IP
- Or set up ingress/load balancer

### Storage Architecture

```
MinIO (k3s)
├── datasets/
│   └── alpaca/          # Shared training data
├── models/
│   ├── tinyllama-v1/    # Saved model checkpoints
│   └── bert-imdb/       # Fine-tuned BERT
└── mlflow/
    └── experiments/     # MLflow artifacts
```

**Mount Pattern**:
```yaml
file_mounts:
  /workspace/data:
    source: s3://datasets
    store: minio
    endpoint_url: http://100.87.186.22:30900
```

### Security Considerations

1. **API Keys**: Vast.ai key in ~/.config/vastai/vast_api_key (not in repo)
2. **MinIO Credentials**: In Kubernetes secrets, referenced by pods
3. **Network**: GPU instances on public internet, use firewall rules
4. **Data**: Sensitive data should be encrypted before upload

### Scaling Patterns

**Single GPU Job**:
```bash
sky launch task.yaml -c job1 --gpus RTX4090:1
```

**Multiple Parallel Jobs**:
```bash
sky launch task.yaml -c job1 --gpus RTX4090:1 &
sky launch task.yaml -c job2 --gpus RTX4090:1 &
sky launch task.yaml -c job3 --gpus A100:1 &
wait
```

**Multi-GPU Training**:
```bash
sky launch task.yaml --gpus RTX4090:4
# Inside task: torch.distributed or DeepSpeed
```

### Cost Optimization

**Spot Instances**:
```yaml
resources:
  cloud: vast
  accelerators: RTX4090:1
  use_spot: true  # 50-70% cheaper
```

**Auto-shutdown**:
```bash
sky autostop cluster-name -i 30  # Stop after 30 min idle
```

**Disk Size**:
```yaml
resources:
  disk_size: 20  # Only what you need
```

### Failure Handling

**GPU Instance Unavailable**:
- SkyPilot automatically tries next cheapest offer
- Built-in retry with exponential backoff

**Job Failure**:
- Logs preserved in `sky logs <cluster>`
- Instance stays running for debugging (unless `--down`)

**Network Issues**:
- MLflow unreachable: Job continues, metrics lost
- MinIO unreachable: Data not persisted
- Both should be reachable via stable public IP

### Monitoring

**SkyPilot Status**:
```bash
sky status          # Running clusters
sky queue           # Job queue
sky logs cluster    # Job logs
```

**Kubernetes Status**:
```bash
kubectl get pods -n mlops
kubectl logs -n mlops deployment/mlflow
```

**Cost Tracking**:
```bash
python skypilot/scripts/cost-tracker.py
```

### Comparison with Other Approaches

| Approach | Cost | Complexity | GPU | Integration | Status |
|----------|------|------------|-----|-------------|--------|
| **SkyPilot + k3s** | Cheap | Medium | Works | Full | Active |
| Virtual Kubelet | Cheap | High | Broken | None | Abandoned |
| Real Nodes | Cheap | Very High | Broken | Partial | Abandoned |
| Cloud k8s (EKS) | Expensive | Low | Works | Full | Alternative |
| Local GPU | Free | Low | Limited | Full | Dev only |

### Future Enhancements

1. **SkyPilot Controller Pod**: Run SkyPilot API server inside k3s
2. **Kubeflow Operator**: Native Kubernetes operator for SkyPilot
3. **Auto-scaling**: Horizontal pod autoscaler triggering GPU jobs
4. **Model Serving**: KServe on k3s serving models trained on Vast.ai
5. **CI/CD**: GitHub Actions triggering Kubeflow → SkyPipeline pipelines