# SkyPilot Guide

## Installation

Already installed. Verify:
```bash
sky check
```

Should show:
```
Vast [compute]: enabled
Kubernetes [compute]: enabled
```

## Basic Commands

### Launch a Task

```bash
# Basic syntax
sky launch task.yaml -c cluster-name

# With auto-cleanup
sky launch task.yaml -c myjob --down

# With specific GPU
sky launch task.yaml --gpus RTX4090:1

# With environment variables
sky launch task.yaml --env KEY=value
```

### Monitor Jobs

```bash
# List all clusters
sky status

# Detailed status
sky status --all

# View logs
sky logs cluster-name

# Stream logs
sky logs cluster-name -f
```

### Manage Clusters

```bash
# Stop (preserve disk, cheaper)
sky stop cluster-name

# Start again
sky start cluster-name

# Terminate (delete everything)
sky down cluster-name

# Terminate all
sky down --all
```

### Cost Control

```bash
# Set auto-shutdown (minutes of idle)
sky autostop cluster-name -i 30

# Cancel auto-shutdown
sky autostop cluster-name -i 0

# Show cost estimate before launching
sky launch task.yaml --dryrun
```

## Task Definition YAML

### Structure

```yaml
task:
  name: my-task           # Task name
  
  resources:
    cloud: vast           # Cloud provider
    accelerators: A100:1  # GPU type and count
    disk_size: 50         # Disk in GB
    use_spot: true        # Use spot instances
  
  env:
    MY_VAR: value         # Environment variables
  
  file_mounts:
    /remote/path:         # Mount storage
      source: s3://bucket
      store: minio
      endpoint_url: ...
  
  setup: |
    # Commands run once when instance is created
    pip install torch transformers
  
  run: |
    # Commands run every time task is executed
    python train.py
```

### Resource Specifications

**GPUs**:
```yaml
accelerators: RTX4090:1    # 1x RTX 4090
accelerators: A100:4       # 4x A100
accelerators: V100:1       # 1x V100
accelerators: T4:1         # 1x Tesla T4
```

**Multiple Clouds**:
```yaml
resources:
  cloud: [vast, runpod, lambda]  # Try in order
  accelerators: RTX4090:1
```

**CPU-only**:
```yaml
resources:
  cloud: kubernetes  # Use local k3s
  cpus: 4
```

### File Mounts

**MinIO**:
```yaml
file_mounts:
  /workspace/data:
    source: s3://datasets
    store: minio
    endpoint_url: http://100.87.186.22:30900
    access_key: minioadmin
    secret_key: minioadmin123
    mode: MOUNT  # or COPY
```

**Cloud Storage** (AWS S3, GCS, etc.):
```yaml
file_mounts:
  /data:
    source: s3://my-bucket
    store: s3
    mode: MOUNT
```

## Advanced Features

### Managed Jobs

Submit jobs that survive cluster preemption:

```bash
# Submit managed job
sky jobs launch task.yaml -n my-experiment

# Check queue
sky jobs queue

# Cancel job
sky jobs cancel my-experiment
```

### Services

Deploy persistent services (APIs, web apps):

```yaml
task:
  name: model-api
  resources:
    cloud: vast
    accelerators: RTX4090:1
    ports: 8000
  
  run: |
    python -m vllm.entrypoints.openai.api_server \
      --model /models/my-model \
      --port 8000
```

```bash
sky serve up task.yaml -n model-service
```

### Spot Instances

Save 50-70% with spot/preemptible instances:

```yaml
resources:
  cloud: vast
  accelerators: A100:1
  use_spot: true
```

**Handling preemption**:
```python
# In your training script
try:
    trainer.train()
except Exception as e:
    # Save checkpoint
    model.save_pretrained("/workspace/checkpoint")
    raise
```

### Multi-Node Training

```yaml
resources:
  accelerators: A100:8
  num_nodes: 2  # 2 nodes, 4 GPUs each
```

Inside training script, use `torch.distributed` or DeepSpeed.

## Integration with Kubernetes

### From Kubernetes Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: skypilot-trigger
spec:
  template:
    spec:
      containers:
      - name: skypilot
        image: berkeleyskypilot/skypilot:latest
        command:
        - sky
        - launch
        - /tasks/train.yaml
        - --cloud
        - vast
        - --yes
      restartPolicy: Never
```

### From Kubeflow Pipeline

See `skypilot/pipelines/kfp-skypilot.py` for full example.

Key pattern:
```python
@dsl.component(base_image="berkeleyskypilot/skypilot:latest")
def gpu_training_step():
    import subprocess
    subprocess.run(["sky", "launch", "task.yaml", "--yes"])
```

## Best Practices

1. **Always use `--down` for one-off jobs**: Avoid forgetting to terminate
2. **Set autostop**: `sky autostop -i 30` as safety net
3. **Use managed jobs for long training**: Survive preemption
4. **Mount data instead of downloading**: Saves time and bandwidth
5. **Log everything to MLflow**: Don't rely on instance storage
6. **Use spot instances**: Massive cost savings
7. **Start small**: Test with cheap GPU before scaling up

## Troubleshooting

**"No instances found"**
```bash
# Check Vast.ai availability
sky show-gpus --cloud vast

# Try different GPU
sky launch task.yaml --gpus V100:1
```

**"Permission denied"**
```bash
# Fix kubeconfig permissions
chmod 600 ~/.kube/config
```

**"Instance creation failed"**
```bash
# Check Vast.ai API key
cat ~/.config/vastai/vast_api_key

# Try again (offers expire quickly)
sky launch task.yaml --yes
```

**"Cannot reach MLflow"**
```bash
# Ensure using correct IP
# Check if MLflow is accessible from internet
curl http://your-public-ip:30500
```

## Resources

- [SkyPilot Docs](https://skypilot.readthedocs.io/)
- [Vast.ai Pricing](https://vast.ai/pricing)
- [SkyPilot GitHub](https://github.com/skypilot-org/skypilot)