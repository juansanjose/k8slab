#!/usr/bin/env bash
# vastai-onstart.sh
# This script runs inside the Vast.ai instance to set up Tailscale and join k3s
# Usage: pass as --onstart-cmd when creating the instance, or run manually after SSH

set -euo pipefail

# Configuration - EDIT THESE BEFORE RUNNING
K3S_URL="${K3S_URL:-https://100.x.y.z:6443}"   # Your laptop's Tailscale IP
K3S_TOKEN="${K3S_TOKEN:-YOUR_TOKEN_HERE}"      # From /var/lib/rancher/k3s/server/node-token

if [[ "$K3S_URL" == "https://100.x.y.z:6443" ]]; then
  echo "ERROR: You must set K3S_URL to your laptop's Tailscale IP"
  echo "Example: export K3S_URL=https://100.64.1.2:6443"
  exit 1
fi

if [[ "$K3S_TOKEN" == "YOUR_TOKEN_HERE" ]]; then
  echo "ERROR: You must set K3S_TOKEN to your k3s server node token"
  echo "Get it from your laptop: sudo cat /var/lib/rancher/k3s/server/node-token"
  exit 1
fi

echo "=== Vast.ai GPU Node Setup ==="
echo ""

# 1. Install Tailscale
echo "[1/6] Installing Tailscale..."
if ! command -v tailscale &> /dev/null; then
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
  apt-get update -qq
  apt-get install -y -qq tailscale
fi

# 2. Start Tailscale
echo "[2/6] Starting Tailscale..."
# For headless/authkey mode (recommended for automation):
# export TS_AUTHKEY=tskey-auth-xxxxxxxxxxxx
# tailscale up --authkey=$TS_AUTHKEY
# For interactive mode (default):
sudo tailscale up || true

# Wait for Tailscale to get an IP
TAILSCALE_IP=""
for i in {1..10}; do
  TAILSCALE_IP=$(sudo tailscale ip -4 2>/dev/null || true)
  if [[ -n "$TAILSCALE_IP" ]]; then
    break
  fi
  echo "Waiting for Tailscale IP... ($i/10)"
  sleep 2
done

if [[ -z "$TAILSCALE_IP" ]]; then
  echo "ERROR: Tailscale did not get an IP address."
  echo "If running non-interactively, set TS_AUTHKEY and use:"
  echo "  tailscale up --authkey=\$TS_AUTHKEY"
  exit 1
fi

echo "Tailscale IP: $TAILSCALE_IP"
echo ""
echo "IMPORTANT: Disable key expiry in the Tailscale admin console for this machine."

# 3. Install NVIDIA Container Toolkit
echo "[3/6] Installing NVIDIA Container Toolkit..."
if ! command -v nvidia-ctk &> /dev/null; then
  # Add NVIDIA package repositories
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  sudo apt-get update -qq
  sudo apt-get install -y -qq nvidia-container-toolkit
fi

# 4. Install k3s agent
echo "[4/6] Installing k3s agent..."
echo "Joining cluster at: $K3S_URL"
curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -

# 5. Configure container runtime for NVIDIA
echo "[5/6] Configuring container runtime..."
# k3s uses its own containerd, so we need to configure it specifically
if [[ -d /var/lib/rancher/k3s/agent/etc/containerd ]]; then
  nvidia-ctk runtime configure --runtime=containerd --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml
elif [[ -S /run/k3s/containerd/containerd.sock ]]; then
  nvidia-ctk runtime configure --runtime=containerd --set-as-default
elif [[ -S /run/containerd/containerd.sock ]]; then
  nvidia-ctk runtime configure --runtime=containerd --set-as-default
else
  nvidia-ctk runtime configure --runtime=docker --set-as-default
fi

# Restart k3s-agent to pick up container runtime changes
echo "Restarting k3s-agent to apply NVIDIA runtime config..."
systemctl restart k3s-agent || true

# 6. Verify
echo "[6/6] Verifying setup..."
sleep 5

if command -v nvidia-smi &>/dev/null; then
  echo ""
  echo "GPU Info:"
  nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || true
else
  echo "WARNING: nvidia-smi not found. GPU drivers may not be installed."
fi

echo ""
echo "========================================"
echo "Setup complete!"
echo ""
echo "Check node status on your laptop with:"
echo "  kubectl get nodes -o wide"
echo ""
echo "If the node is NotReady, check logs:"
echo "  journalctl -u k3s-agent -f"
echo "========================================"
