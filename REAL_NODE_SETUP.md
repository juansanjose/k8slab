# Real Kubernetes GPU Nodes via Vast.ai + Tailscale

This is the **proper** way to add GPU nodes to your Kubernetes cluster - by having them join as **real worker nodes** via Tailscale VPN.

## Architecture

```
Your Laptop (Control Plane)
├─ k3s Server (API, Scheduler, Controller)
├─ MLflow, MinIO, PostgreSQL (local services)
├─ Tailscale (100.87.186.22)
│
│    Tailscale VPN Mesh
│    ═══════════════════
│
▼
Vast.ai Container (Worker Node)
├─ tailscaled (userspace networking)
├─ containerd (native snapshotter)
├─ kubelet (k3s agent)
├─ GPU (RTX 4090 / A100)
│
├─ Runs as REAL node in cluster
├─ kubectl exec works
├─ kubectl logs works
├─ Cluster DNS works (mlflow.mlops.svc.cluster.local)
└─ GPU scheduling works (nvidia.com/gpu)
```

## Why This is Better Than Virtual Kubelet

| Feature | Virtual Kubelet | Real Node |
|---------|----------------|-----------|
| `kubectl exec` | ❌ Doesn't work | ✅ Works perfectly |
| `kubectl logs` | ❌ Doesn't work | ✅ Works perfectly |
| Cluster DNS | ❌ Not available | ✅ Full DNS resolution |
| Services | ❌ Can't reach | ✅ Can reach all services |
| GPU | ✅ Works | ✅ Works |
| Storage | ❌ Ephemeral only | ✅ Can use PVCs |
| Network Policies | ❌ Not applicable | ✅ Works |
| Monitoring | ❌ Limited | ✅ Full metrics |
| Honesty | ❌ Fake node | ✅ Real node |

## Prerequisites

1. **k3s server** running on your laptop
2. **Tailscale** installed and running
3. **Vast.ai API key**
4. **Tailscale auth key** (from https://login.tailscale.com/admin/settings/keys)

## Quick Start

### Step 1: Prepare k3s Server

Run on your laptop:

```bash
# Setup k3s server to accept worker connections via Tailscale
bash scripts/setup-k3s-server-for-workers.sh
```

This will:
- Add TLS-SAN for your Tailscale IP
- Open firewall for Tailscale connections
- Generate worker join configuration
- Save config to `~/.vastai/worker-config.env`

### Step 2: Create Vast.ai Worker Node

```bash
# Set your environment
export VASTAI_KEY="your-vastai-key"
export TS_AUTHKEY="tskey-auth-xxxxxxxxxxxx"

# Load server config
source ~/.vastai/worker-config.env

# Create worker node
bash scripts/create-vastai-worker.sh
```

Or manually via Vast.ai web UI:
1. Create instance with Ubuntu 22.04
2. Set environment variables:
   - `K3S_URL=https://100.87.186.22:6443` (your Tailscale IP)
   - `K3S_TOKEN=K10...` (from server)
   - `TS_AUTHKEY=tskey-auth-...`
3. Pass onstart script: `scripts/vastai-worker-setup.sh`

### Step 3: Verify Node Joined

```bash
# Watch nodes join
kubectl get nodes -w

# Should see something like:
# NAME             STATUS   ROLES           AGE   VERSION
# panzamachine     Ready    control-plane   1d    v1.34.6+k3s1
# vastai-worker-1  Ready    <none>          30s   v1.34.6+k3s1
```

### Step 4: Run GPU Workloads

```bash
# Submit GPU test job
kubectl apply -f mlops-lab/examples/gpu-training-real-node.yaml

# Watch logs (works because it's a real node!)
kubectl logs -f job/gpu-training-real-node

# Exec into running pod (also works!)
kubectl exec -it job/gpu-training-real-node -- bash
```

## How It Works

### Worker Setup Script (`vastai-worker-setup.sh`)

The script handles all the container limitations:

1. **Creates /dev/kmsg** - Required by kubelet, normally missing in Docker containers
2. **Installs Tailscale** - Joins your Tailnet for cluster connectivity
3. **Sets up proxy** - SOCKS5 proxy for reaching cluster via Tailscale
4. **Installs k3s agent** - Downloads k3s binary
5. **Configures containerd** - Uses `native` snapshotter (overlayfs doesn't work in Docker)
6. **Sets up cgroups** - Creates required cgroup hierarchies
7. **Starts k3s agent** - Joins your cluster as a real node

### Key Configuration

**k3s agent config** (`/etc/rancher/k3s/config.yaml`):
```yaml
# Use native snapshotter (no overlayfs)
snapshotter: native

# Disable control plane components (this is a worker)
disable-apiserver: true
disable-controller-manager: true
disable-scheduler: true

# Cgroup configuration for containers
kubelet-arg:
  - "cgroup-driver=cgroupfs"
  - "fail-swap-on=false"
```

**Tailscale networking**:
```bash
# Container runs tailscaled in userspace mode
tailscaled --tun=userspace-networking --socks5-server=localhost:1080

# Joins your Tailnet
tailscale up --authkey=$TS_AUTHKEY

# Now container can reach cluster via Tailscale IPs
```

## Files

```
scripts/
├── setup-k3s-server-for-workers.sh  # Prepare laptop for worker connections
├── create-vastai-worker.sh          # Create Vast.ai instance as worker
└── vastai-worker-setup.sh           # Run inside Vast.ai container

mlops-lab/examples/
├── gpu-training-real-node.yaml      # GPU test job
├── jupyter-gpu.yaml                 # Jupyter on GPU node
└── test-real-node.sh                # Test script
```

## Troubleshooting

### Node stuck in NotReady

```bash
# Check kubelet logs on worker
kubectl logs -n kube-system daemonset/kube-proxy --tail=50

# Or SSH into Vast.ai instance and check:
tail -f /var/log/rancher/k3s-agent.log
```

### Container can't reach cluster

```bash
# Test from inside container
kubectl exec -it <pod> -- curl -k https://10.43.0.1:443/healthz

# Check Tailscale status
kubectl exec -it <pod> -- tailscale status
```

### GPU not available

```bash
# Check if nvidia-device-plugin is running
kubectl get pods -n kube-system | grep nvidia

# Check node capacity
kubectl describe node vastai-worker-1 | grep nvidia.com/gpu
```

### Overlayfs error

The setup uses `snapshotter: native` which avoids overlayfs. If you still see errors:

```bash
# SSH into worker and check containerd
kubectl exec -it <pod-on-worker> -- cat /etc/containerd/config.toml
```

## Cost Comparison

| Approach | Cost | Complexity | Honesty |
|----------|------|------------|---------|
| Virtual Kubelet | $0.02-0.50/hr | Medium | ❌ Fake node |
| Real Node (this) | $0.02-0.50/hr | Medium | ✅ Real node |
| Cloud k8s (GKE/EKS) | $2-5/hr | Low | ✅ Real node |
| RunPod k8s | $0.50-1/hr | Low | ✅ Real node |

## Advantages

1. **Real Kubernetes experience** - Everything works as expected
2. **kubectl exec/logs** - Debug and monitor normally
3. **Cluster services** - Access MLflow, MinIO, databases
4. **Storage** - Use PVCs for persistent data
5. **GPU scheduling** - Standard nvidia.com/gpu resource
6. **Network policies** - Isolate workloads
7. **Metrics** - Full Prometheus/Grafana support

## Limitations

1. **Vast.ai containers** still have Docker-in-Docker limitations
2. **No systemd** - processes run directly, not as services
3. **Container restarts** - if Vast.ai container dies, node disappears
4. **No HA** - single control plane on laptop

## Next Steps

1. Test the setup: `bash mlops-lab/examples/test-real-node.sh`
2. Run LLM training with cluster services
3. Build Kubeflow pipelines that use GPU nodes
4. Set up auto-scaling (cluster-autoscaler)

## Migration from Virtual Kubelet

If you were using the old Virtual Kubelet approach:

```bash
# 1. Remove virtual node
kubectl delete node virtual-vastai

# 2. Delete old controller
kubectl delete -f vastai-kubelet/deploy/

# 3. Setup real worker nodes (follow steps above)
bash scripts/setup-k3s-server-for-workers.sh
bash scripts/create-vastai-worker.sh

# 4. Update pod specs
# Remove: nodeName: virtual-vastai
# Add: nodeSelector: vast.ai/gpu: "true"
```

## Summary

This approach gives you **real Kubernetes nodes** on cheap Vast.ai GPUs, connected to your local cluster via Tailscale. It's the proper way to build a hybrid cluster for ML workloads.