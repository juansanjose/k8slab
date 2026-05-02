#!/bin/bash
# Tailscale Setup Script for RunPod GPU Instances
# This script installs and configures Tailscale on RunPod instances
# allowing them to reach the local k3s cluster via Tailscale VPN

set -e

echo "=== Tailscale Setup for RunPod ==="

# Check if already installed
if command -v tailscale &> /dev/null; then
    echo "Tailscale already installed"
else
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# Start Tailscale
echo "Starting Tailscale..."
tailscaled &
sleep 2

# Authenticate with Tailscale
# Auth key should be passed as environment variable
if [ -z "$TAILSCALE_AUTHKEY" ]; then
    echo "ERROR: TAILSCALE_AUTHKEY not set"
    echo "Please set TAILSCALE_AUTHKEY environment variable"
    exit 1
fi

echo "Authenticating with Tailscale..."
tailscale up --authkey="$TAILSCALE_AUTHKEY" --accept-routes

# Wait for IP
echo "Waiting for Tailscale IP..."
for i in {1..10}; do
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
    if [ -n "$TS_IP" ]; then
        echo "Tailscale IP: $TS_IP"
        break
    fi
    echo "Waiting... ($i/10)"
    sleep 2
done

if [ -z "$TS_IP" ]; then
    echo "ERROR: Failed to get Tailscale IP"
    exit 1
fi

# Test connectivity to k3s
echo ""
echo "Testing connectivity to k3s cluster..."
echo -n "MLflow (100.87.186.22:30500): "
if curl -s --max-time 5 http://100.87.186.22:30500 > /dev/null; then
    echo "✅ REACHABLE"
else
    echo "❌ NOT REACHABLE"
fi

echo -n "MinIO (100.87.186.22:30900): "
if curl -s --max-time 5 http://100.87.186.22:30900/minio/health/live > /dev/null; then
    echo "✅ REACHABLE"
else
    echo "❌ NOT REACHABLE"
fi

echo ""
echo "=== Tailscale Setup Complete ==="
echo "Tailscale IP: $TS_IP"
echo "k3s services accessible via Tailscale VPN"

# Keep tailscaled running in background
echo "Tailscale daemon running..."
wait