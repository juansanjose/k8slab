#!/usr/bin/env bash
# docker-build.sh
# Build the Docker image used by all wrapper scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-k8s-scripts}"

echo "Building Docker image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"

echo ""
echo "Done! Image '$IMAGE_NAME' is ready."
echo "You can now run any script with its docker- wrapper."
