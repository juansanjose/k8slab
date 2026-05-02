#!/bin/bash

# MLOps Lab - API Key Manager
# Manages API keys for cloud providers and services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/../.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if .env exists and has keys
check_keys() {
    echo "Checking API keys..."
    echo ""
    
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found at $ENV_FILE"
        echo "Please create it with your API keys"
        return 1
    fi
    
    # Source the .env file
    set -a
    source "$ENV_FILE"
    set +a
    
    # Check RunPod
    if [ -n "$RunPod_Key" ]; then
        echo -e "RunPod:     ${GREEN}✓ Set${NC} (${RunPod_Key:0:10}...)"
    else
        echo -e "RunPod:     ${RED}✗ Missing${NC}"
    fi
    
    # Check Vast.ai
    if [ -n "$VASTAI_KEY" ]; then
        echo -e "Vast.ai:    ${GREEN}✓ Set${NC} (${VASTAI_KEY:0:10}...)"
    else
        echo -e "Vast.ai:    ${YELLOW}⚠ Optional${NC}"
    fi
    
    # Check Tailscale
    if [ -n "$TS_AUTHKEY" ]; then
        echo -e "Tailscale:  ${GREEN}✓ Set${NC} (${TS_AUTHKEY:0:15}...)"
    else
        echo -e "Tailscale:  ${YELLOW}⚠ Optional${NC}"
    fi
    
    echo ""
}

# Sync keys to Kubernetes secrets
sync_to_k8s() {
    log_info "Syncing API keys to Kubernetes..."
    
    set -a
    source "$ENV_FILE"
    set +a
    
    # Create/update secret with actual values
    cat > /tmp/mlops-secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloud-credentials
  namespace: mlops
type: Opaque
stringData:
  runpod-api-key: "${RunPod_Key:-}"
  vastai-api-key: "${VASTAI_KEY:-}"
  tailscale-authkey: "${TS_AUTHKEY:-}"
  minio-access-key: "minioadmin"
  minio-secret-key: "minioadmin123"
  postgres-user: "mlops"
  postgres-password: "mlops123"
EOF
    
    kubectl apply -f /tmp/mlops-secrets.yaml
    rm -f /tmp/mlops-secrets.yaml
    
    log_success "API keys synced to Kubernetes"
}

# Update SkyPilot config with API keys
update_skypilot() {
    log_info "Updating SkyPilot configuration..."
    
    set -a
    source "$ENV_FILE"
    set +a
    
    # Check SkyPilot config directory
    SKY_CONFIG_DIR="$HOME/.sky"
    mkdir -p "$SKY_CONFIG_DIR"
    
    # SkyPilot picks up keys from environment automatically
    # But let's verify
    if sky check 2>/dev/null | grep -q "RunPod.*enabled"; then
        log_success "SkyPilot already configured with RunPod"
    else
        log_warn "SkyPilot RunPod not configured"
        echo "Make sure RunPod_Key is set in your .env file"
    fi
}

# Show current status
status() {
    echo "========================================"
    echo "  API Key Management"
    echo "========================================"
    echo ""
    
    check_keys
    
    echo "Kubernetes Secrets:"
    if kubectl get secret cloud-credentials -n mlops > /dev/null 2>&1; then
        echo -e "  cloud-credentials: ${GREEN}✓ Exists${NC}"
    else
        echo -e "  cloud-credentials: ${RED}✗ Missing${NC}"
    fi
    
    echo ""
    echo "SkyPilot Backends:"
    sky check 2>/dev/null | grep -E "(RunPod|Vast)" || echo "  Not configured"
}

# Interactive setup
setup_interactive() {
    echo "========================================"
    echo "  API Key Setup"
    echo "========================================"
    echo ""
    echo "This will help you configure API keys."
    echo "You can get keys from:"
    echo "  RunPod:    https://www.runpod.io/console/user/settings"
    echo "  Vast.ai:   https://cloud.vast.ai/account/"
    echo "  Tailscale: https://login.tailscale.com/admin/settings/keys"
    echo ""
    
    read -p "RunPod API Key (press Enter to skip): " runpod_key
    read -p "Vast.ai API Key (press Enter to skip): " vastai_key
    read -p "Tailscale Auth Key (press Enter to skip): " tailscale_key
    
    # Create/update .env file
    cat > "$ENV_FILE" <<EOF
# MLOps Lab Environment Variables
# Generated on $(date)

# RunPod API Key
RunPod_Key=${runpod_key:-}

# Vast.ai API Key (optional)
VASTAI_KEY=${vastai_key:-}

# Tailscale Auth Key (optional)
TS_AUTHKEY=${tailscale_key:-}

# K3s Configuration
K3S_TOKEN=${K3S_TOKEN:-}
EOF
    
    log_success ".env file created/updated"
    
    # Sync to Kubernetes
    sync_to_k8s
    
    echo ""
    echo "Setup complete!"
}

# Main
case "${1:-status}" in
    "check")
        check_keys
        ;;
    "sync")
        sync_to_k8s
        ;;
    "setup")
        setup_interactive
        ;;
    "status")
        status
        ;;
    "update-skypilot")
        update_skypilot
        ;;
    *)
        echo "Usage: $0 {check|sync|setup|status|update-skypilot}"
        echo ""
        echo "Commands:"
        echo "  check           - Check API keys"
        echo "  sync            - Sync keys to Kubernetes"
        echo "  setup           - Interactive setup"
        echo "  status          - Show full status"
        echo "  update-skypilot - Update SkyPilot config"
        ;;
esac
