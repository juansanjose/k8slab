#!/usr/bin/env bash
# docker-destroy-vastai-node.sh
# Run destroy-vastai-node.sh inside a Docker container

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-k8s-scripts}"

# Ensure image exists
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Image '$IMAGE_NAME' not found. Building..."
  "$SCRIPT_DIR/docker-build.sh"
fi

docker run --rm -it \
  -v "$PROJECT_ROOT:/workspace" \
  -v "$HOME/.kube:/root/.kube:ro" \
  -v "$HOME/.vastai:/root/.vastai:ro" \
  -e VASTAI_API_KEY \
  -w /workspace \
  "$IMAGE_NAME" \
  scripts/destroy-vastai-node.sh "$@"
