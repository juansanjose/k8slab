# Kubernetes AI/ML Lab Environment

This repo contains everything you need to build a cheap, hands-on lab for learning how Kubernetes handles AI/ML workloads — including GPU scheduling, Kubeflow, NVIDIA GPU Operator, and KAI-Scheduler.

---

## Quick Start: Vast.ai GPU + Local k3s (Cheapest Option)

**Architecture:** Your Linux laptop runs k3s control plane. A cheap Vast.ai GPU instance joins as a worker node via Tailscale VPN.

**Expected cost:** $5-12/month if you practice ~5 hours/week.

### Files

| File | Purpose |
|------|---------|
| `VAST_K3S_TAILSCALE_GUIDE.md` | Full step-by-step guide |
| `scripts/setup-k3s-server.sh` | Reconfigure local k3s to bind to Tailscale IP |
| `scripts/vastai-find-and-create.sh` | Find cheapest GPU, create instance, auto-configure it |
| `scripts/vastai-onstart.sh` | Run inside Vast.ai instance to install Tailscale + join k3s |
| `scripts/test-gpu-pod.sh` | Deploy a test pod to verify GPU scheduling |
| `scripts/install-gpu-operator.sh` | Install NVIDIA GPU Operator on the cluster |
| `scripts/destroy-vastai-node.sh` | Clean up and destroy the Vast.ai instance |
| `manifests/gpu-test-pods.yaml` | Test pods for CUDA and PyTorch GPU verification |
| `manifests/kubeflow-pipelines-lite.yaml` | Lightweight Kubeflow Pipelines install |

### Step-by-Step

1. **Install Tailscale** on your laptop and sign up (free)
2. **Run `scripts/setup-k3s-server.sh`** to reconfigure k3s for Tailscale
3. **Rent a Vast.ai GPU instance** using `scripts/vastai-find-and-create.sh` (interactive finder + auto-setup) or manually rent and run `scripts/vastai-onstart.sh` inside it
4. **Verify the node joined** with `kubectl get nodes`
5. **Run `scripts/install-gpu-operator.sh`** to enable GPU support
6. **Test with `scripts/test-gpu-pod.sh`** or `kubectl apply -f manifests/gpu-test-pods.yaml`
7. **Install Kubeflow** with `kubectl apply -f manifests/kubeflow-pipelines-lite.yaml`
8. **When done, run `scripts/destroy-vastai-node.sh`** to stop billing

---

## Documentation

| Document | What it covers |
|----------|---------------|
| `README.md` | This project overview |
| `ARCHITECTURE.md` | Deep dive into the Virtual Kubelet codebase |
| `COMPARISON.md` | Comparison with Karmada, SLURM, KAI-Scheduler |
| `SLURM_CONTAINERS.md` | How SLURM schedules containers and GPUs |
| `VAST_K3S_TAILSCALE_GUIDE.md` | Connecting Vast.ai GPU to local k3s |
| `LAB_SETUP_GUIDE.md` | Broader lab setup options (cloud, on-prem) |

---

## Scripts

All scripts are in `scripts/` and are executable.

```bash
# Make sure they are executable
chmod +x scripts/*.sh

# Run any script
./scripts/setup-k3s-server.sh
```

---

## Manifests

Kubernetes manifests are in `manifests/`.

```bash
# Test GPU scheduling
kubectl apply -f manifests/gpu-test-pods.yaml

# Install lightweight Kubeflow Pipelines
kubectl apply -f manifests/kubeflow-pipelines-lite.yaml
```

---

## Learning Path

1. **Day 1-2:** Set up cluster + GPU node. Verify `nvidia-smi` works in a pod.
2. **Day 3-4:** Install NVIDIA GPU Operator. Explore GPU metrics with DCGM.
3. **Day 5-7:** Install Kubeflow Pipelines. Build a simple training pipeline.
4. **Day 8-10:** Install KAI-Scheduler. Experiment with gang scheduling, queues, GPU sharing.
5. **Day 11-14:** Deploy an inference workload (vLLM, Triton) with autoscaling.

---

## Cost Comparison

| Approach | Monthly Cost (5 hrs/week) | Complexity |
|----------|--------------------------|------------|
| Vast.ai + local k3s | $5-12 | Medium |
| GCP GKE (Spot T4) | $0-15 (with $300 credit) | Low |
| AWS EKS (Spot G4dn) | $0-20 (with free tier) | Medium |
| All local (no GPU) | $0 | N/A (no GPU) |

---

## Notes

- This is a **learning environment**, not production-ready.
- The Virtual Kubelet project in this repo is experimental and for educational purposes.
- For production AI/ML on Kubernetes, consider **KAI-Scheduler** or **NVIDIA GPU Operator** on managed Kubernetes (GKE, EKS, AKS).
