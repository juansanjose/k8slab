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

# Create required directories
mkdir -p /var/lib/tailscale /run/tailscale

# Check if systemd is available (not in containers)
if pidof systemd > /dev/null 2>&1; then
    echo "  Using systemd to start tailscaled..."
    sudo systemctl start tailscaled || true
else
    echo "  systemd not available (container), starting tailscaled manually..."
    # Start tailscaled in background with userspace networking + SOCKS5 proxy
    # SOCKS5 proxy is required because containers don't have /dev/net/tun
    sudo tailscaled --tun=userspace-networking --socks5-server=localhost:1080 --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock > /var/log/tailscaled.log 2>&1 &
    sleep 3
fi

# Check if authkey is available for non-interactive mode
if [[ -n "${TS_AUTHKEY:-}" ]]; then
    echo "  Using authkey for non-interactive authentication..."
    sudo tailscale up --authkey="$TS_AUTHKEY" --accept-routes --netfilter-mode=off
else
    echo "  For interactive mode, visit the URL below to authenticate:"
    echo "  (Or set TS_AUTHKEY env var for non-interactive mode)"
    sudo tailscale up --accept-routes --netfilter-mode=off || true
fi

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

# In containers, we need to use Tailscale's SOCKS5 proxy for connectivity
# because --tun=userspace-networking doesn't intercept all traffic automatically
if ! pidof systemd > /dev/null 2>&1; then
  echo "  Container detected, configuring Tailscale SOCKS5 proxy..."
  
  # Install proxychains and socat for TCP proxying through SOCKS5
  apt-get install -y -qq proxychains4 socat 2>/dev/null || true
  
  # Configure proxychains to use tailscale SOCKS5 proxy
  # Note: proxy_dns is disabled because tailscale DNS doesn't work well in containers
  mkdir -p /etc
  printf '%s\n' 'strict_chain' 'tcp_read_time_out 15000' 'tcp_connect_time_out 8000' '' '[ProxyList]' 'socks5 127.0.0.1 1080' > /etc/proxychains4.conf
  
  # Extract server IP from K3S_URL
  SERVER_IP=$(echo "$K3S_URL" | sed -E 's|https?://||' | sed -E 's|:.*||')
  echo "  Setting up TCP proxy: localhost:6444 -> $SERVER_IP:6443 via SOCKS5"
  
  # Start TCP proxy using proxychains + socat
  # This forwards localhost:6445 to the k3s server via tailscale SOCKS5 proxy
  # Note: We use 6445 instead of 6444 to avoid conflict with k3s internal load balancer
  pkill -f "proxychains4.*socat" 2>/dev/null || true
  sleep 1
  nohup proxychains4 socat TCP-LISTEN:6445,fork TCP:$SERVER_IP:6443 > /var/log/tcp-proxy.log 2>&1 &
  sleep 2
  
  # Update K3S_URL to use local proxy
  echo "  Using local proxy: https://127.0.0.1:6445"
  export K3S_URL="https://127.0.0.1:6445"
fi

curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -

# Start k3s agent manually if systemd is not available (containers)
if ! pidof systemd > /dev/null 2>&1; then
  echo "  systemd not available, starting k3s agent manually..."
  # Kill any existing k3s agent
  pkill -f "k3s agent" 2>/dev/null || true
  sleep 2
  
  # Start k3s agent pointing to local TCP proxy (which forwards via SOCKS5)
  # Use native snapshotter because overlayfs is not supported in containers
  export K3S_URL="https://127.0.0.1:6445"
  mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml << EOF
snapshotter: native
EOF
  nohup k3s agent --snapshotter native > /var/log/k3s-agent.log 2>&1 &
  echo "  k3s agent started, waiting for connection..."
  sleep 20
fi

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
if pidof systemd > /dev/null 2>&1; then
  systemctl restart k3s-agent || true
else
  # For containers, restart pointing to local TCP proxy
  pkill -f "k3s agent" 2>/dev/null || true
  sleep 2
  export K3S_URL="https://127.0.0.1:6445"
  nohup k3s agent --snapshotter native > /var/log/k3s-agent.log 2>&1 &
fi

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

# Check k3s agent status
echo ""
echo "k3s agent status:"
if pgrep -f "k3s agent" > /dev/null; then
  echo "  k3s agent is running"
else
  echo "  WARNING: k3s agent is not running"
fi

# Test connectivity to server
echo ""
echo "Testing connectivity to k3s server at $K3S_URL..."
if curl -k --max-time 10 "$K3S_URL" > /dev/null 2>&1; then
  echo "  Successfully connected to k3s server"
else
  echo "  WARNING: Cannot connect to k3s server"
  echo "  This may be due to:"
  echo "    - Firewall blocking port 6443"
  echo "    - k3s server not running"
  echo "    - Network connectivity issues"
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
