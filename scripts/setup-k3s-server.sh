#!/usr/bin/env bash
# setup-k3s-server.sh
# Run this on your local Linux laptop to set up k3s server bound to Tailscale IP

set -euo pipefail

# Check prerequisites
if ! command -v curl &>/dev/null; then
  echo "ERROR: curl is required but not installed."
  exit 1
fi

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)

if [[ -z "$TAILSCALE_IP" ]]; then
  echo "ERROR: Tailscale is not running or not installed."
  echo "Install Tailscale first: https://tailscale.com/download"
  echo "Then run: sudo tailscale up"
  exit 1
fi

echo "Your Tailscale IP: $TAILSCALE_IP"
echo ""

# Save existing token if k3s is already running
if [[ -f /var/lib/rancher/k3s/server/node-token ]]; then
  echo "Existing k3s node token:"
  sudo cat /var/lib/rancher/k3s/server/node-token
  echo ""
  echo "^ SAVE THIS TOKEN - you'll need it for the Vast.ai node"
  echo ""
fi

read -p "This will stop and reconfigure k3s to bind to Tailscale IP. Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo "Stopping k3s (if running)..."
sudo systemctl stop k3s 2>/dev/null || true
sudo systemctl disable k3s 2>/dev/null || true

echo "Uninstalling old k3s (if present)..."
if command -v k3s-uninstall.sh &>/dev/null; then
  sudo k3s-uninstall.sh || true
fi

echo "Installing k3s with Tailscale IP configuration..."
echo "Flags: --tls-san $TAILSCALE_IP --bind-address 0.0.0.0 --advertise-address $TAILSCALE_IP --node-ip $TAILSCALE_IP --flannel-iface tailscale0"
sudo curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san $TAILSCALE_IP --bind-address 0.0.0.0 --advertise-address $TAILSCALE_IP --node-ip $TAILSCALE_IP --flannel-iface tailscale0" sh -

echo ""
echo "k3s server installed. Waiting for it to be ready..."
sleep 10

# Wait for node to be ready (with timeout)
READY=false
for i in {1..30}; do
  if sudo k3s kubectl get nodes 2>/dev/null | grep -q "Ready"; then
    READY=true
    break
  fi
  echo "Waiting for k3s node to be Ready... ($i/30)"
  sleep 2
done

if [[ "$READY" != "true" ]]; then
  echo "ERROR: k3s node did not become Ready within 60 seconds."
  echo "Check logs: sudo journalctl -u k3s -f"
  exit 1
fi

echo ""
echo "========================================"
echo "k3s server is running on Tailscale IP: $TAILSCALE_IP:6443"
echo ""
echo "Node token (save this for Vast.ai node):"
sudo cat /var/lib/rancher/k3s/server/node-token
echo ""
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Open Tailscale admin console and disable key expiry for this machine"
echo "2. Allow firewall: sudo ufw allow in on tailscale0 && sudo ufw allow 6443/tcp"
echo "3. Rent a Vast.ai GPU instance and run the onstart script"
