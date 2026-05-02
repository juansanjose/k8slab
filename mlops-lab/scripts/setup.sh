#!/bin/bash
set -e

# MLOps Lab - One-Command Setup Script
# This script automates the entire local + cloud GPU setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running with sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "This script needs to run with sudo for k3s installation"
        echo "Please run: sudo ./setup.sh"
        exit 1
    fi
}

# Install k3s if not present
install_k3s() {
    log_info "Checking k3s installation..."
    
    if command -v k3s &> /dev/null; then
        log_success "k3s already installed"
        return 0
    fi
    
    log_info "Installing k3s..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
    
    # Wait for k3s to be ready
    log_info "Waiting for k3s to be ready..."
    sleep 10
    until kubectl get nodes > /dev/null 2>&1; do
        sleep 2
    done
    
    # Fix kubeconfig permissions
    chmod 644 /etc/rancher/k3s/k3s.yaml
    
    log_success "k3s installed and ready"
}

# Deploy MLOps services to k3s
deploy_services() {
    log_info "Deploying MLOps services to k3s..."
    
    cd "$PROJECT_ROOT"
    
    # Create namespace
    kubectl apply -f base/namespaces.yaml
    
    # Deploy core services
    kubectl apply -k base/
    
    # Wait for all pods to be ready
    log_info "Waiting for services to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgres -n mlops --timeout=120s
    kubectl wait --for=condition=ready pod -l app=minio -n mlops --timeout=120s
    kubectl wait --for=condition=ready pod -l app=mlflow -n mlops --timeout=300s
    
    log_success "All MLOps services deployed"
}

# Install SkyPilot
install_skypilot() {
    log_info "Checking SkyPilot installation..."
    
    if command -v sky &> /dev/null; then
        log_success "SkyPilot already installed"
        return 0
    fi
    
    log_info "Installing SkyPilot..."
    pip install -U "skypilot[runpod]"
    
    log_success "SkyPilot installed"
}

# Configure SkyPilot
configure_skypilot() {
    log_info "Configuring SkyPilot..."
    
    # Check if API keys are configured
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        log_warn "No .env file found. Creating from example..."
        cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
        log_warn "Please edit $PROJECT_ROOT/.env with your API keys"
    fi
    
    # Source environment variables
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
    
    log_success "SkyPilot configured"
}

# Setup SSH tunnel service
setup_tunnel() {
    log_info "Setting up SSH tunnel service..."
    
    # Create systemd service for tunnel management
    cat > /etc/systemd/system/mlops-tunnel.service << EOF
[Unit]
Description=MLOps Lab SSH Tunnel
After=network.target

[Service]
Type=simple
User=$SUDO_USER
ExecStart=/bin/bash -c 'while true; do ssh -N -R 30500:localhost:30500 -R 30900:localhost:30900 -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes gpu-test-ssh 2>&1 || sleep 10; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log_success "SSH tunnel service created (not started - will start with first training job)"
}

# Main setup function
main() {
    echo "========================================"
    echo "  MLOps Lab - Automated Setup"
    echo "========================================"
    echo ""
    
    check_sudo
    install_k3s
    deploy_services
    install_skypilot
    configure_skypilot
    setup_tunnel
    
    echo ""
    echo "========================================"
    log_success "Setup complete!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $PROJECT_ROOT/.env with your API keys"
    echo "  2. Run: ./scripts/train.sh llm"
    echo ""
    echo "Services available at:"
    echo "  MLflow: http://localhost:30500"
    echo "  MinIO:  http://localhost:30901"
}

main "$@"
