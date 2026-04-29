#!/bin/bash
# vastai-worker-setup.sh
# Sets up a Vast.ai container as a REAL Kubernetes worker node
# This runs INSIDE the Vast.ai container

set -euo pipefail

# Configuration
K3S_URL="${K3S_URL:-}"
K3S_TOKEN="${K3S_TOKEN:-}"
TS_AUTHKEY="${TS_AUTHKEY:-}"
NODE_NAME="${NODE_NAME:-vastai-worker-$(hostname)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARNING:${NC} $*"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $*"; }

die() { error "$*"; exit 1; }

# Validate inputs
[[ -z "$K3S_URL" ]] && die "K3S_URL not set. Example: https://100.87.186.22:6443"
[[ -z "$K3S_TOKEN" ]] && die "K3S_TOKEN not set. Get it from: sudo cat /var/lib/rancher/k3s/server/node-token"
[[ -z "$TS_AUTHKEY" ]] && die "TS_AUTHKEY not set. Get it from: https://login.tailscale.com/admin/settings/keys"

log "=== Vast.ai Worker Node Setup ==="
log "Node: $NODE_NAME"
log "Server: $K3S_URL"
log ""

# ============================================================================
# STEP 1: Setup /dev/kmsg (required by kubelet)
# ============================================================================
log "[1/8] Setting up /dev/kmsg..."

if [[ ! -e /dev/kmsg ]]; then
    log "  Creating fake /dev/kmsg..."
    mknod /dev/kmsg c 1 11 2>/dev/null || true
    # If mknod fails, create a pipe as fallback
    if [[ ! -e /dev/kmsg ]]; then
        rm -f /dev/kmsg
        mkfifo /dev/kmsg 2>/dev/null || true
        # Start a background process that reads from it
        (while true; do cat <>/dev/null 2>/dev/null; done) <> /dev/kmsg &
    fi
fi

# Also ensure /dev/console exists for containerd
if [[ ! -e /dev/console ]]; then
    ln -sf /dev/pts/0 /dev/console 2>/dev/null || true
fi

log "  /dev/kmsg setup complete"

# ============================================================================
# STEP 2: Install Tailscale
# ============================================================================
log "[2/8] Installing Tailscale..."

if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# Create required directories
mkdir -p /var/lib/tailscale /run/tailscale /var/run/tailscale

# Start tailscaled
log "  Starting tailscaled..."
pkill tailscaled 2>/dev/null || true
sleep 1

tailscaled \
    --tun=userspace-networking \
    --socks5-server=localhost:1080 \
    --state=/var/lib/tailscale/tailscaled.state \
    --socket=/run/tailscale/tailscaled.sock \
    > /var/log/tailscaled.log 2>&1 &

sleep 3

# Authenticate
log "  Authenticating with Tailscale..."
tailscale up --authkey="$TS_AUTHKEY" --accept-routes --netfilter-mode=off

# Wait for IP
TAILSCALE_IP=""
for i in {1..15}; do
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
    [[ -n "$TAILSCALE_IP" ]] && break
    log "  Waiting for Tailscale IP... ($i/15)"
    sleep 2
done

[[ -z "$TAILSCALE_IP" ]] && die "Tailscale failed to get IP"
log "  Tailscale IP: $TAILSCALE_IP"

# ============================================================================
# STEP 3: Setup proxy for cluster connectivity
# ============================================================================
log "[3/8] Setting up cluster proxy..."

# Extract server IP from K3S_URL
SERVER_IP=$(echo "$K3S_URL" | sed -E 's|https?://||' | sed -E 's|:.*||')

# Install proxychains and socat
apt-get update -qq && apt-get install -y -qq proxychains4 socat 2>/dev/null || true

# Configure proxychains
mkdir -p /etc
cat > /etc/proxychains4.conf <> 'EOF'
strict_chain
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5 127.0.0.1 1080
EOF

# Set proxy environment
export HTTP_PROXY=socks5://localhost:1080
export HTTPS_PROXY=socks5://localhost:1080
export http_proxy=socks5://localhost:1080
export https_proxy=socks5://localhost:1080
export NO_PROXY=localhost,127.0.0.1

# Test connectivity to k3s server
log "  Testing k3s server connectivity..."
if curl -k --max-time 10 "$K3S_URL" > /dev/null 2>&1; then
    log "  Connected to k3s server!"
else
    warn "Cannot connect directly, will use proxychains..."
fi

# ============================================================================
# STEP 4: Install k3s agent
# ============================================================================
log "[4/8] Installing k3s agent..."

# Download k3s binary
if [[ ! -f /usr/local/bin/k3s ]]; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true INSTALL_K3S_SKIP_ENABLE=true sh -
fi

# Create necessary directories
mkdir -p /etc/rancher/k3s /var/lib/rancher/k3s/agent/etc/containerd /run/k3s/containerd /run/kubepods /run/flannel

# ============================================================================
# STEP 5: Configure k3s for container environment
# ============================================================================
log "[5/8] Configuring k3s for container environment..."

# Create k3s config
cat > /etc/rancher/k3s/config.yaml <> EOF
# Use native snapshotter (overlayfs doesn't work in Docker containers)
snapshotter: native

# Disable unnecessary components for worker node
disable-apiserver: true
disable-controller-manager: true
disable-scheduler: true
disable-cloud-controller: true

# Kubelet configuration for containers
kubelet-arg:
  # Use cgroupfs instead of systemd cgroup driver
  - "cgroup-driver=cgroupfs"
  # Disable node validation (we're in a container)
  - "fail-swap-on=false"
  # Set root directory
  - "root-dir=/var/lib/kubelet"
  # Lower eviction thresholds for containers with limited disk
  - "eviction-hard=memory.available<100Mi,nodefs.available<10%"
  - "eviction-soft=memory.available<200Mi,nodefs.available<20%"
  # Reduce housekeeping intervals
  - "housekeeping-interval=10s"
  # Disable CPU manager (not available in containers)
  - "cpu-manager-policy=none"

# Containerd configuration
container-runtime-endpoint: unix:///run/k3s/containerd/containerd.sock

# Node configuration
node-name: ${NODE_NAME}
node-label:
  - "vast.ai/gpu=true"
  - "vast.ai/provider=vastai"
  - "node-type=worker"

# Network configuration
flannel-iface: tailscale0

# Disable metrics server (not needed for workers)
disable-metrics-server: true
EOF

# ============================================================================
# STEP 6: Create required cgroup mounts
# ============================================================================
log "[6/8] Setting up cgroups..."

# Mount cgroup filesystems if not already mounted
mount -t tmpfs none /sys/fs/cgroup 2>/dev/null || true

# Create cgroup directories
for subsystem in cpu cpuacct memory blkio pids; do
    mkdir -p /sys/fs/cgroup/$subsystem 2>/dev/null || true
    if ! mountpoint -q /sys/fs/cgroup/$subsystem; then
        mount -t cgroup -o $subsystem cgroup /sys/fs/cgroup/$subsystem 2>/dev/null || true
    fi
done

# Create unified cgroup v2 hierarchy if supported
if [[ -f /proc/filesystems ]] && grep -q cgroup2 /proc/filesystems; then
    mkdir -p /sys/fs/cgroup/unified 2>/dev/null || true
    if ! mountpoint -q /sys/fs/cgroup/unified; then
        mount -t cgroup2 none /sys/fs/cgroup/unified 2>/dev/null || true
    fi
fi

# Ensure kubepods cgroup exists
mkdir -p /sys/fs/cgroup/kubepods 2>/dev/null || true

log "  Cgroup setup complete"

# ============================================================================
# STEP 7: Install and configure containerd
# ============================================================================
log "[7/8] Setting up containerd..."

# Ensure containerd directories exist
mkdir -p /run/containerd /var/lib/containerd

# Create containerd config
cat > /etc/containerd/config.toml <> EOF
version = 2

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "rancher/mirrored-pause:3.6"
  
  [plugins."io.containerd.grpc.v1.cri".containerd]
    snapshotter = "native"
    default_runtime_name = "runc"
    
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      runtime_type = "io.containerd.runc.v2"
      
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = false

[plugins."io.containerd.grpc.v1.cri".cni]
  bin_dir = "/opt/cni/bin"
  conf_dir = "/etc/cni/net.d"
EOF

# ============================================================================
# STEP 8: Start k3s agent
# ============================================================================
log "[8/8] Starting k3s agent..."

# Kill any existing k3s processes
pkill -f "k3s agent" 2>/dev/null || true
pkill -f containerd 2>/dev/null || true
sleep 2

# Set environment for k3s
export K3S_URL="$K3S_URL"
export K3S_TOKEN="$K3S_TOKEN"

# Start k3s agent in foreground
log "  Starting k3s agent..."
log "  This may take a few minutes..."
log ""

# Create log directory
mkdir -p /var/log/rancher

# Start k3s agent
exec k3s agent \
    --server "$K3S_URL" \
    --token "$K3S_TOKEN" \
    --config /etc/rancher/k3s/config.yaml \
    --data-dir /var/lib/rancher/k3s \
    --node-name "$NODE_NAME" \
    --flannel-iface tailscale0 \
    2>&1 | tee /var/log/rancher/k3s-agent.log