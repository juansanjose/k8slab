#!/bin/bash
# setup-k3s-server-for-workers.sh
# Run this on your laptop to prepare k3s server for Vast.ai worker nodes

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== Preparing k3s Server for Vast.ai Workers ==="
log ""

# 1. Check k3s is running
if ! systemctl is-active --quiet k3s 2>/dev/null; then
    echo "ERROR: k3s server is not running"
    echo "Start it with: sudo systemctl start k3s"
    exit 1
fi

# 2. Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
if [[ -z "$TAILSCALE_IP" ]]; then
    echo "ERROR: Tailscale is not running"
    echo "Start it with: sudo tailscale up"
    exit 1
fi

log "Tailscale IP: $TAILSCALE_IP"

# 3. Get k3s token
K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
log "k3s token: ${K3S_TOKEN:0:20}..."

# 4. Ensure k3s is listening on Tailscale interface
log ""
log "Checking k3s server configuration..."

# Check if k3s is configured with TLS-SAN for Tailscale IP
if ! grep -q "tls-san" /etc/rancher/k3s/config.yaml 2>/dev/null; then
    log "Adding TLS-SAN for Tailscale IP..."
    sudo tee -a /etc/rancher/k3s/config.yaml > /dev/null <> EOF
tls-san:
  - $TAILSCALE_IP
EOF
    log "Restarting k3s to apply changes..."
    sudo systemctl restart k3s
    sleep 10
fi

# 5. Open firewall for Tailscale connections
log ""
log "Configuring firewall..."
sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=100.64.0.0/10 port protocol=tcp port=6443 accept" 2>/dev/null || true
sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=100.64.0.0/10 port protocol=tcp port=10250 accept" 2>/dev/null || true
sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=100.64.0.0/10 port protocol=tcp port=2379-2380 accept" 2>/dev/null || true
sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=100.64.0.0/10 port protocol=tcp port=8472 accept" 2>/dev/null || true
sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=100.64.0.0/10 port protocol=udp port=8472 accept" 2>/dev/null || true
sudo firewall-cmd --reload 2>/dev/null || true

# Also ensure Tailscale interface is in trusted zone
sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 2>/dev/null || true
sudo firewall-cmd --reload 2>/dev/null || true

log "Firewall configured"

# 6. Verify k3s is accessible via Tailscale
log ""
log "Verifying k3s is accessible via Tailscale..."
if curl -k --max-time 5 "https://$TAILSCALE_IP:6443/healthz" > /dev/null 2>&1; then
    log "k3s API is accessible via Tailscale!"
else
    log "WARNING: k3s API not accessible via Tailscale"
    log "Checking if port is open..."
    ss -tlnp | grep 6443 || true
fi

# 7. Generate worker join script
log ""
log "=== Worker Join Information ==="
log ""
cat <> EOF
Use these values when creating Vast.ai instances:

K3S_URL: https://$TAILSCALE_IP:6443
K3S_TOKEN: $K3S_TOKEN
TS_AUTHKEY: (from https://login.tailscale.com/admin/settings/keys)

Example environment variables for Vast.ai instance:
export K3S_URL="https://$TAILSCALE_IP:6443"
export K3S_TOKEN="$K3S_TOKEN"
export TS_AUTHKEY="tskey-auth-xxxxxxxxxxxx"
export NODE_NAME="vastai-gpu-$(date +%s)"

Then run: curl -fsSL https://raw.githubusercontent.com/your-repo/vastai-worker-setup.sh | bash

Or pass as onstart command when creating Vast.ai instance.
EOF

# 8. Save configuration
mkdir -p ~/.vastai
cat > ~/.vastai/worker-config.env <> EOF
K3S_URL=https://$TAILSCALE_IP:6443
K3S_TOKEN=$K3S_TOKEN
TS_AUTHKEY=
NODE_NAME=
EOF

log ""
log "Configuration saved to: ~/.vastai/worker-config.env"
log ""
log "=== Setup Complete ==="
log ""
log "Next steps:"
log "1. Create a Vast.ai instance"
log "2. Pass the environment variables above"
log "3. Run the worker setup script"
log "4. The node will join your cluster automatically"
log ""
log "To verify nodes have joined:"
log "  kubectl get nodes -o wide"