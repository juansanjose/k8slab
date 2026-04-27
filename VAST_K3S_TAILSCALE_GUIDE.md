# Vast.ai GPU Node + Local k3s via Tailscale

A step-by-step guide to adding a cheap Vast.ai GPU instance as a worker node to your local Linux k3s cluster, using Tailscale for seamless networking.

---

## Architecture

```
+-------------------+        Tailscale VPN         +-------------------+
|  Your Laptop      |  <------------------------>  |  Vast.ai Instance |
|  (k3s server)     |      100.x.x.x mesh          |  (k3s agent)      |
|  Linux            |                            |  NVIDIA GPU       |
+-------------------+                            +-------------------+
       |                                                  |
       |  kubectl schedule pod                            |  nvidia-smi
       v                                                  v
   +--------+                                       +------------+
   |  Pod   | ----------------> runs on ------------> |  Container |
   +--------+                                       +------------+
```

---

## Prerequisites

- Linux laptop/desktop with k3s installed (or willingness to install it)
- Vast.ai account with $5-10 credit
- Tailscale account (free for personal use)

---

## Step 1: Install Tailscale on Your Laptop

```bash
# Add Tailscale repo and install
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt-get update
sudo apt-get install -y tailscale

# Connect to Tailscale
sudo tailscale up
```

A browser window will open for authentication. Sign up/log in to Tailscale.

**Verify:**
```bash
tailscale ip -4
# Should print something like: 100.x.y.z
```

**Disable key expiry** (so you don't have to re-authenticate):
```bash
# In the Tailscale admin console (https://login.tailscale.com/admin/machines)
# Find your laptop, click the "..." menu, and disable key expiry.
```

---

## Step 2: Configure k3s to Bind to Tailscale IP

By default, k3s binds to your local network IP. You need it to also listen on the Tailscale IP so the Vast.ai node can reach it.

```bash
# If k3s is already running, get the token first
sudo cat /var/lib/rancher/k3s/server/node-token
# Save this token — you'll need it for the Vast.ai node

# Stop k3s
sudo systemctl stop k3s

# Reinstall k3s binding to Tailscale IP and all interfaces
# Replace 100.x.y.z with your actual Tailscale IP from Step 1
sudo curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san 100.x.y.z --bind-address 0.0.0.0 --advertise-address 100.x.y.z --node-ip 100.x.y.z" sh -

# Verify k3s is listening on Tailscale IP
sudo ss -tlnp | grep 6443
# You should see 0.0.0.0:6443 or 100.x.y.z:6443
```

**Important:** The `--tls-san` flag adds your Tailscale IP to the Kubernetes API certificate. Without this, the remote node will reject the connection due to TLS certificate mismatch.

---

## Step 3: Allow Tailscale Traffic Through Your Firewall

```bash
# If using UFW
sudo ufw allow in on tailscale0
sudo ufw allow 6443/tcp

# Or if using iptables directly
sudo iptables -A INPUT -i tailscale0 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 6443 -j ACCEPT
```

---

## Step 4: Find and Rent a Cheap GPU on Vast.ai

### Option A: Automated (Recommended)

Use the provided script to automatically find the cheapest compatible GPU and create the instance:

```bash
# Make sure you have the Vast.ai CLI installed
pip install vastai
vastai set api-key YOUR_API_KEY

# Run the interactive finder
./scripts/vastai-find-and-create.sh
```

This script will:
1. Auto-detect your k3s URL and token
2. Search all available GPUs dynamically (not locked to specific models)
3. Show the top 10 cheapest options
4. Let you pick one interactively
5. Create the instance with auto-setup via onstart script
6. Poll until the instance is ready

**Environment variables:**
```bash
export MAX_DPH=0.30        # Max price per hour (default: 0.50)
export MIN_COMPUTE_CAP=700 # Minimum CUDA compute capability (default: 700)
./scripts/vastai-find-and-create.sh
```

### Option B: Manual

If you prefer to manually select and configure the instance:

#### Install Vast CLI

```bash
pip install vastai
vastai set api-key YOUR_API_KEY
```

Get your API key from: https://cloud.vast.ai/cli/

#### Search for Cheap GPU Instances

```bash
# Search for RTX 3090 or A4000 instances, sorted by price
vastai search offers 'gpu_name == RTX_3090' -o 'dph+'

# Or for even cheaper options (RTX 3070, 3080)
vastai search offers 'gpu_name == RTX_3070' -o 'dph+'

# Or search for instances with CUDA >= 11.8 and at least 1 GPU
vastai search offers 'compute_cap >= 800 num_gpus>=1' -o 'dph+'
```

Look for:
- **Direct SSH** capable instances (faster, no proxy)
- **Reliability > 0.95**
- **Price < $0.50/hr** for learning

#### Recommended Template for Kubernetes GPU Workloads

Use the **PyTorch** or **CUDA** base image so NVIDIA drivers and container runtime are pre-installed:

```bash
# Create instance with PyTorch image (includes CUDA, drivers, container toolkit)
# Replace OFFER_ID with the ID from search results
vastai create instance OFFER_ID \
  --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime \
  --disk 32 \
  --ssh \
  --direct
```

Or use a Vast.ai template that already has Docker + NVIDIA support:
```bash
# Search for templates with CUDA pre-installed
vastai search offers 'cuda_vers >= 12' -o 'dph+'
```

**Wait for the instance to reach "running" state:**
```bash
vastai show instances
```

---

## Step 5: SSH into the Vast.ai Instance and Set It Up

```bash
# Get connection info
vastai show instance INSTANCE_ID

# SSH in (use the port and IP from the output)
ssh -p SSH_PORT root@INSTANCE_IP
```

### Inside the Vast.ai Instance

```bash
# 1. Install Tailscale
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale

# 2. Connect to your Tailscale network
tailscale up
# Authenticate in the browser (or use auth key for headless)

# 3. Verify Tailscale IP
tailscale ip -4
# Should show something like 100.a.b.c

# 4. Install k3s agent
curl -sfL https://get.k3s.io | K3S_URL=https://100.x.y.z:6443 K3S_TOKEN=YOUR_K3S_TOKEN sh -

# Replace:
#   100.x.y.z = your laptop's Tailscale IP from Step 1
#   YOUR_K3S_TOKEN = the token from Step 2 (/var/lib/rancher/k3s/server/node-token)
```

---

## Step 6: Verify the Node Joined

On your **laptop**:

```bash
kubectl get nodes -o wide
```

You should see two nodes:
- Your laptop (control-plane,master)
- The Vast.ai instance (worker)

```
NAME              STATUS   ROLES                  AGE   VERSION
your-laptop       Ready    control-plane,master   1d    v1.29.4+k3s1
vastai-instance   Ready    <none>                 2m    v1.29.4+k3s1
```

---

## Step 7: Install NVIDIA GPU Support

### On the Vast.ai Node (SSH in)

Vast.ai instances with CUDA images usually have NVIDIA drivers pre-installed. Verify:

```bash
nvidia-smi
# Should show GPU info
```

Install the NVIDIA Container Toolkit so Kubernetes can use GPUs:

```bash
# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
apt-get install -y nvidia-container-toolkit

# Configure containerd (k3s uses containerd)
nvidia-ctk runtime configure --runtime=containerd --set-as-default
systemctl restart k3s-agent

# Or if using docker:
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
```

### Install NVIDIA Device Plugin (on laptop)

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml
```

### Verify GPU is visible

```bash
kubectl get nodes -o json | jq '.items[].status.capacity | with_entries(select(.key | contains("nvidia")))'
```

You should see:
```json
{
  "nvidia.com/gpu": "1"
}
```

---

## Step 8: Test GPU Scheduling

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cuda-test
spec:
  containers:
  - name: cuda
    image: nvidia/cuda:12.4.1-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  nodeSelector:
    kubernetes.io/hostname: vastai-instance
EOF

kubectl logs cuda-test
```

You should see `nvidia-smi` output from the Vast.ai GPU.

---

## Step 9: Install NVIDIA GPU Operator (Recommended)

Instead of manual setup, let the GPU Operator manage everything:

```bash
helm repo add nvidia https://helm.ngc.io/nvidia
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=true \
  --set toolkit.enabled=true
```

This handles drivers, container toolkit, device plugin, and monitoring automatically.

---

## Step 10: Cost Management

### Stop the Instance (keep storage, stop GPU billing)

```bash
vastai stop instance INSTANCE_ID
```

### Start it again later

```bash
vastai start instance INSTANCE_ID
# SSH in and restart k3s-agent if needed:
# systemctl restart k3s-agent
```

### Destroy when done

```bash
vastai destroy instance INSTANCE_ID
```

---

## Troubleshooting

### Node shows NotReady

```bash
# On Vast.ai node, check k3s-agent logs
journalctl -u k3s-agent -f

# Common issue: k3s-agent can't reach API server
# Verify Tailscale is up on both ends
ping 100.x.y.z  # from Vast.ai node to laptop
```

### TLS certificate error when joining

You forgot `--tls-san` when installing k3s. Reinstall k3s on the laptop with the flag.

### GPU not showing in node capacity

```bash
# On Vast.ai node
nvidia-smi  # verify drivers work
nvidia-ctk runtime configure --runtime=containerd --set-as-default
systemctl restart k3s-agent

# Then restart device plugin pod
kubectl delete pod -n kube-system -l name=nvidia-device-plugin-daemonset
```

### Tailscale connection drops

```bash
# Check Tailscale status on both ends
tailscale status

# If behind restrictive NAT, enable NAT traversal
tailscale up --netfilter-mode=on
```

---

## Expected Costs

| Component | Cost |
|-----------|------|
| Tailscale | Free (personal plan) |
| k3s on laptop | Free |
| Vast.ai RTX 3090 | ~$0.20-0.50/hr |
| Vast.ai storage | ~$0.01-0.02/GB/month |
| **Total (5 hrs/week practice)** | **~$5-12/month** |

---

## Next Steps

1. Install **Kubeflow Pipelines** for ML workflow orchestration
2. Install **KAI-Scheduler** for GPU-aware batch scheduling
3. Deploy a training job (PyTorch/TensorFlow) with GPU resources
4. Experiment with **NVIDIA GPU Operator** features (MIG, time-slicing, MPS)
