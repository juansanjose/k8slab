# Troubleshooting Guide

## Common Issues

### SkyPilot Issues

**"Vast [compute]: disabled"**
```bash
# Fix: Set API key
mkdir -p ~/.config/vastai
echo "your-api-key" > ~/.config/vastai/vast_api_key

# Verify
sky check
```

**"No instances found" or "no_such_ask"**
```bash
# Vast.ai offers expire quickly
# Just try again
sky launch task.yaml --yes

# Or check available GPUs
sky show-gpus --cloud vast
```

**"Instance creation failed"**
```bash
# Check if you have sufficient balance
# Vast.ai requires prepaid balance

# Try different GPU
sky launch task.yaml --gpus [RTX4090,RTX3090]
```

**"Permission denied" for kubeconfig**
```bash
# Fix permissions
chmod 600 ~/.kube/config

# Or set explicitly
export KUBECONFIG=~/.kube/config
sky check kubernetes
```

### GPU Issues

**"CUDA not available"**
```bash
# Inside SkyPilot task, check:
nvidia-smi
python -c "import torch; print(torch.cuda.is_available())"

# If false, instance may still be initializing
# Wait 1-2 minutes and retry
```

**"Out of memory"**
```bash
# Solutions:
# 1. Use smaller batch size
# 2. Enable gradient checkpointing
# 3. Use smaller model
# 4. Get GPU with more VRAM

# In task env:
BATCH_SIZE=1
```

**"nvidia-smi not found"**
```bash
# Rare - GPU driver not loaded
# Terminate and retry
sky down cluster-name
sky launch task.yaml -c cluster-name
```

### MLOps Service Issues

**MLflow not reachable from GPU**
```bash
# Test from GPU instance
curl http://100.87.186.22:30500

# If timeout:
# 1. Check MLflow is running
kubectl get pods -n mlops

# 2. Check firewall (allow port 30500)
sudo firewall-cmd --list-ports

# 3. Check Tailscale (if using)
tailscale status
```

**MinIO connection refused**
```bash
# Check MinIO pod
kubectl logs -n mlops deployment/minio

# Check NodePort
curl http://localhost:30900/minio/health/live

# Verify credentials match
echo $AWS_ACCESS_KEY_ID  # Should be minioadmin
```

**MLflow crashlooping**
```bash
# Check logs
kubectl logs -n mlops deployment/mlflow

# Likely OOM - increase memory limit
kubectl edit deployment mlflow -n mlops
# Change memory limit to 2Gi
```

### Network Issues

**"Cannot reach k3s from GPU"**

GPU instances are on the public internet. k3s services need to be accessible:

```bash
# Option 1: Use public IP
MLFLOW_URI=http://your-public-ip:30500

# Option 2: Use Tailscale IP
MLFLOW_URI=http://100.x.x.x:30500

# Option 3: Port forward via SSH
curl --proxy socks5h://localhost:1080 http://mlflow:5000
```

**"DNS resolution fails"**
```bash
# Use IP addresses instead of hostnames
# In SkyPilot task:
env:
  MLFLOW_TRACKING_URI: http://100.87.186.22:30500  # IP, not hostname
```

### Kubernetes Issues

**Pod stuck in Pending**
```bash
# Check events
kubectl describe pod <pod-name>

# Common causes:
# - Node has taint: Add toleration
# - Insufficient resources: Check node capacity
# - Image pull failure: Check image name
```

**"ImagePullBackOff"**
```bash
# Check image exists
kubectl describe pod <pod-name> | grep -A 5 Events

# Try pulling manually
docker pull <image>
```

**k3s not responding**
```bash
# Check k3s service
sudo systemctl status k3s

# Restart if needed
sudo systemctl restart k3s

# Check kubeconfig
export KUBECONFIG=~/.kube/config
kubectl cluster-info
```

### Data Issues

**"Dataset not found" on GPU**
```bash
# Check mount worked
ls -la /workspace/data

# Verify MinIO bucket exists
aws --endpoint-url http://100.87.186.22:30900 s3 ls s3://datasets

# In task YAML, ensure mount is correct:
file_mounts:
  /workspace/data:
    source: s3://datasets
    store: minio
    endpoint_url: http://100.87.186.22:30900
```

**"Model not saved"**
```bash
# Check write permissions
ls -la /workspace/models

# Ensure MinIO credentials are correct
env | grep AWS

# Test write
aws --endpoint-url http://100.87.186.22:30900 s3 cp test.txt s3://models/
```

## Debug Commands

### SkyPilot Debug

```bash
# Verbose logging
sky launch task.yaml -v

# Check instance details
sky status --all

# SSH into instance for debugging
sky ssh cluster-name

# Check logs
sky logs cluster-name
sky logs cluster-name --controller
```

### Kubernetes Debug

```bash
# Pod details
kubectl describe pod <pod> -n <namespace>

# Container logs
kubectl logs <pod> -n <namespace> --previous  # crashed pod

# Execute into pod
kubectl exec -it <pod> -n <namespace> -- /bin/bash

# Node resources
kubectl describe node
```

### Network Debug

```bash
# Test connectivity from GPU instance
curl -v http://100.87.186.22:30500
curl -v http://100.87.186.22:30900/minio/health/live

# Check ports are open
sudo ss -tlnp | grep -E "30500|30900|30800"

# Test Tailscale connectivity
ping 100.87.186.22
tailscale ping 100.87.186.22
```

## Getting Help

### SkyPilot
- GitHub Issues: https://github.com/skypilot-org/skypilot/issues
- Documentation: https://skypilot.readthedocs.io/
- Slack: https://skypilot-slack.herokuapp.com/

### Vast.ai
- Discord: https://discord.gg/vastai
- Documentation: https://vast.ai/docs/

### Kubernetes
- kubectl cheat sheet: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- k3s docs: https://docs.k3s.io/

## Reset Everything

If nothing works, start fresh:

```bash
# 1. Terminate all GPU instances
sky down --all --yes

# 2. Delete all Kubernetes resources
kubectl delete -k mlops-lab/base/
kubectl delete ns kubeflow

# 3. Redeploy services
kubectl apply -k mlops-lab/base/

# 4. Test with simple job
make gpu-test
```