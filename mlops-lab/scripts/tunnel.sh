#!/bin/bash

# MLOps Lab - SSH Tunnel Manager
# Automates SSH tunnel creation for cloud instance connectivity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if tunnel is active
check_tunnel() {
    local cluster_name=${1:-gpu-training}
    
    # Check if we can reach local services from RunPod
    if timeout 5 ssh "$cluster_name" "curl -s --max-time 2 http://localhost:30500 > /dev/null" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Start tunnel
start_tunnel() {
    local cluster_name=${1:-gpu-training}
    
    log_info "Starting SSH tunnel for cluster: $cluster_name"
    
    # Check if cluster exists
    if ! sky status | grep -q "$cluster_name"; then
        log_error "Cluster $cluster_name not found"
        return 1
    fi
    
    # Start tunnel in background
    ssh -N -R 30500:localhost:30500 -R 30900:localhost:30900 \
        -o ServerAliveInterval=60 \
        -o ExitOnForwardFailure=yes \
        -o StrictHostKeyChecking=no \
        "$cluster_name" &
    
    TUNNEL_PID=$!
    echo $TUNNEL_PID > /tmp/mlops-tunnel.pid
    
    # Wait for tunnel to be active
    sleep 3
    if check_tunnel "$cluster_name"; then
        log_success "SSH tunnel active (PID: $TUNNEL_PID)"
        return 0
    else
        log_error "Failed to establish tunnel"
        kill $TUNNEL_PID 2>/dev/null
        return 1
    fi
}

# Stop tunnel
stop_tunnel() {
    if [ -f /tmp/mlops-tunnel.pid ]; then
        PID=$(cat /tmp/mlops-tunnel.pid)
        if kill -0 $PID 2>/dev/null; then
            kill $PID
            rm -f /tmp/mlops-tunnel.pid
            log_success "SSH tunnel stopped"
        else
            log_warn "Tunnel process not running"
        fi
    else
        log_warn "No tunnel PID file found"
    fi
}

# Show tunnel status
status() {
    local cluster_name=${1:-gpu-training}
    
    echo "SSH Tunnel Status"
    echo "================="
    
    if [ -f /tmp/mlops-tunnel.pid ]; then
        PID=$(cat /tmp/mlops-tunnel.pid)
        if kill -0 $PID 2>/dev/null; then
            echo -e "Process: ${GREEN}Running${NC} (PID: $PID)"
        else
            echo -e "Process: ${RED}Not running${NC}"
        fi
    else
        echo -e "Process: ${YELLOW}Not started${NC}"
    fi
    
    echo ""
    echo "Connectivity Test:"
    if check_tunnel "$cluster_name"; then
        echo -e "  MLflow (localhost:30500): ${GREEN}Reachable${NC}"
    else
        echo -e "  MLflow (localhost:30500): ${RED}Not reachable${NC}"
    fi
}

# Install as systemd service
install_service() {
    log_info "Installing SSH tunnel as systemd service..."
    
    cat > /tmp/mlops-tunnel.service <<EOF
[Unit]
Description=MLOps Lab SSH Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=$USER
ExecStart=/bin/bash -c 'ssh -N -R 30500:localhost:30500 -R 30900:localhost:30900 -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes gpu-training & echo $$ > /tmp/mlops-tunnel.pid'
ExecStop=/bin/bash -c 'kill $(cat /tmp/mlops-tunnel.pid) 2>/dev/null; rm -f /tmp/mlops-tunnel.pid'
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    sudo mv /tmp/mlops-tunnel.service /etc/systemd/system/
    sudo systemctl daemon-reload
    
    log_success "Service installed"
    log_info "Start with: sudo systemctl start mlops-tunnel"
    log_info "Enable auto-start: sudo systemctl enable mlops-tunnel"
}

# Main
case "${1:-status}" in
    "start")
        start_tunnel "${2:-}"
        ;;
    "stop")
        stop_tunnel
        ;;
    "status")
        status "${2:-}"
        ;;
    "restart")
        stop_tunnel
        sleep 2
        start_tunnel "${2:-}"
        ;;
    "install")
        install_service
        ;;
    "check")
        if check_tunnel "${2:-}"; then
            echo "Tunnel is active"
            exit 0
        else
            echo "Tunnel is not active"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart|install|check} [cluster-name]"
        echo ""
        echo "Commands:"
        echo "  start [cluster]   - Start SSH tunnel"
        echo "  stop              - Stop SSH tunnel"
        echo "  status [cluster]  - Show tunnel status"
        echo "  restart [cluster] - Restart tunnel"
        echo "  install           - Install as systemd service"
        echo "  check [cluster]   - Quick connectivity check"
        ;;
esac
