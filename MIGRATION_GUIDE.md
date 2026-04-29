# Migration Guide: Virtual Kubelet → Real Nodes

## What Changed

**Before (Virtual Kubelet):**
- Fake node in Kubernetes
- Containers isolated from cluster
- Couldn't use kubectl exec/logs
- Couldn't reach cluster services
- Basically just remote Docker orchestration

**After (Real Nodes):**
- Real worker nodes via Tailscale VPN
- Full cluster integration
- kubectl exec/logs work
- Can reach MLflow, MinIO, PostgreSQL
- Real Kubernetes experience

## Architecture Comparison

### Virtual Kubelet (OLD)
```
┌─────────────────────────────────┐
│ k3s Cluster                     │
│  ├─ panzamachine (control-plane)│
│  └─ virtual-vastai (FAKE)       │
│       │                         │
│       │ HTTP API calls          │
│       ▼                         │
│  ┌──────────────────────────┐   │
│  │ Vast.ai Container        │   │
│  │ (ISOLATED - no network)  │   │
│  │ Can't reach MLflow/MinIO │   │
│  └──────────────────────────┘   │
└─────────────────────────────────┘
```

### Real Nodes (NEW)
```
┌─────────────────────────────────┐
│ k3s Cluster                     │
│  ├─ panzamachine (control-plane)│
│  └─ vastai-worker-1 (REAL)      │
│       │                         │
│       │ Tailscale VPN           │
│       ▼                         │
│  ┌──────────────────────────┐   │
│  │ Vast.ai Container        │   │
│  │ (ON NETWORK)             │   │
│  │ Can reach MLflow/MinIO   │   │
│  │ kubectl exec works!      │   │
│  └──────────────────────────┘   │
└─────────────────────────────────┘
```

## New Files

```
scripts/
├── setup-k3s-server-for-workers.sh  # Prepare your laptop
├── create-vastai-worker.sh          # Create GPU worker node
└── vastai-worker-setup.sh           # Runs inside Vast.ai container

mlops-lab/examples/
├── gpu-training-real-node.yaml      # Real GPU job
├── jupyter-gpu.yaml                 # Jupyter on GPU
└── test-real-node.sh                # Test everything

REAL_NODE_SETUP.md                  # Full documentation
```

## Steps to Migrate

### 1. Clean Up Old Virtual Kubelet

```bash
# Remove the fake virtual node
kubectl delete node virtual-vastai

# Delete old controller (optional - keep if you want both)
kubectl delete -f vastai-kubelet/deploy/
```

### 2. Prepare Your Laptop

```bash
# Get your Tailscale IP
tailscale ip -4
# Should show: 100.87.186.22

# Get k3s token (run on your laptop)
sudo cat /var/lib/rancher/k3s/server/node-token

# Add TLS-SAN for Tailscale IP
sudo tee /etc/rancher/k3s/config.yaml <> EOF
tls-san:
  - 100.87.186.22
EOF

# Restart k3s
sudo systemctl restart k3s

# Open firewall
sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0
sudo firewall-cmd --reload
```

### 3. Create Real Worker Node

Get a Tailscale auth key from: https://login.tailscale.com/admin/settings/keys

```bash
# Set environment
export VASTAI_KEY="your-vastai-api-key"
export TS_AUTHKEY="tskey-auth-xxxxxxxxxxxx"
export K3S_URL="https://100.87.186.22:6443"
export K3S_TOKEN="K10xxxxxxxxxx::server:xxxxxxxxxx"

# Create worker
bash scripts/create-vastai-worker.sh
```

### 4. Verify

```bash
# Watch node join (takes 2-3 minutes)
kubectl get nodes -w

# Should see:
# NAME              STATUS   ROLES           AGE   VERSION
# panzamachine      Ready    control-plane   1d    v1.34.6+k3s1
# vastai-worker-1   Ready    <none>          30s   v1.34.6+k3s1
```

### 5. Test GPU Workload

```bash
# Submit GPU test
kubectl apply -f mlops-lab/examples/gpu-training-real-node.yaml

# Watch logs (THIS WORKS NOW!)
kubectl logs -f job/gpu-training-real-node

# Exec into pod (THIS ALSO WORKS!)
kubectl exec -it job/gpu-training-real-node -- nvidia-smi
```

## What's Different in Pod Specs

### Before (Virtual Kubelet)
```yaml
spec:
  nodeName: virtual-vastai  # Fake node
  tolerations:
  - key: "virtual-kubelet.io/provider"
    effect: "NoSchedule"
```

### After (Real Node)
```yaml
spec:
  nodeSelector:
    vast.ai/gpu: "true"     # Real GPU node
  # No tolerations needed!
```

## What Works Now

✅ **kubectl exec** - Get shell in running GPU pods  
✅ **kubectl logs** - Stream logs from GPU pods  
✅ **Cluster DNS** - Reach services like `mlflow.mlops.svc.cluster.local`  
✅ **Services** - Access MLflow, MinIO from GPU pods  
✅ **PVCs** - Mount persistent storage  
✅ **Network Policies** - Isolate GPU workloads  
✅ **Metrics** - See GPU utilization in Prometheus  
✅ **Port Forwarding** - Access Jupyter directly  

## Example: Full MLflow Integration

```python
# train.py running on Vast.ai GPU node
import mlflow
import torch
from transformers import AutoModelForCausalLM

# Connect to YOUR MLflow (works because it's a real node!)
mlflow.set_tracking_uri("http://mlflow.mlops.svc.cluster.local:5000")
mlflow.set_experiment("llm-finetuning")

with mlflow.start_run():
    # Log params
    mlflow.log_param("model", "TinyLlama")
    mlflow.log_param("epochs", 3)
    
    # Load and train on GPU
    model = AutoModelForCausalLM.from_pretrained(
        "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
        device_map="auto"
    )
    
    # ... training code ...
    
    # Log metrics
    mlflow.log_metric("loss", 0.5)
    mlflow.log_metric("accuracy", 0.95)
    
    # Save model to MinIO (works!)
    mlflow.pytorch.log_model(model, "model")

# Results are in YOUR cluster!
```

## Troubleshooting

### Node not joining

```bash
# Check k3s server is listening on Tailscale IP
curl -k https://100.87.186.22:6443/healthz

# Check Tailscale connection from worker
# (SSH into Vast.ai instance via web UI)
tailscale status
tailscale ping 100.87.186.22
```

### Container can't start (CDI error)

Vast.ai has a CDI device injection bug. Workarounds:
1. Try different GPU model (RTX 3090 vs A100)
2. Use CPU-only containers for testing
3. Wait for Vast.ai to fix (contact support)

### Cgroup errors

The setup script handles most cgroup issues. If you see errors:
```bash
# SSH into worker and check
kubectl exec -it <pod-on-worker> -- bash
cat /var/log/rancher/k3s-agent.log | tail -50
```

## Cost

Same as before - only pay Vast.ai for GPU time:
- RTX 4090: ~$0.30-0.50/hour
- A100: ~$0.50-1.00/hour
- Your laptop services: FREE

## Summary

We went from fake nodes to real nodes, giving you a proper Kubernetes cluster with cheap GPU workers. The Vast.ai containers are now **actual members** of your cluster, not isolated islands.

**This is the right way to do it.**