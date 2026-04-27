#!/usr/bin/env bash
# destroy-vastai-node.sh
# Clean up the Vast.ai instance and remove it from k3s

set -euo pipefail

INSTANCE_ID="${1:-}"
NODE_NAME="${2:-}"

if [[ -z "$INSTANCE_ID" ]]; then
  echo "Usage: $0 <INSTANCE_ID> [NODE_NAME]"
  echo ""
  echo "Find your instance ID with: vastai show instances"
  echo "Find node name with: kubectl get nodes"
  exit 1
fi

echo "Removing node from k3s cluster..."
if [[ -n "$NODE_NAME" ]]; then
  kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data || true
  kubectl delete node "$NODE_NAME" || true
else
  echo "WARNING: No node name provided. Skipping kubectl drain/delete."
  echo "You may need to manually remove the node: kubectl delete node <node-name>"
fi

echo ""
echo "Destroying Vast.ai instance $INSTANCE_ID..."
vastai destroy instance "$INSTANCE_ID" || {
  echo "WARNING: Failed to destroy instance. It may already be stopped/destroyed."
  echo "Check status with: vastai show instances"
}

echo ""
echo "Cleanup complete. GPU billing stopped."
