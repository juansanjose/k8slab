#!/bin/bash
set -e

# MLOps Lab - Training Job Submission Script
# Abstracts SkyPilot and cloud GPU provisioning

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prereqs() {
    log_info "Checking prerequisites..."
    
    if ! command -v sky &> /dev/null; then
        log_error "SkyPilot not found. Run setup.sh first"
        exit 1
    fi
    
    if ! kubectl get nodes > /dev/null 2>&1; then
        log_error "k3s not accessible. Run setup.sh first"
        exit 1
    fi
    
    # Check if services are accessible
    if ! curl -s http://localhost:30500 > /dev/null 2>&1; then
        log_error "MLflow not accessible. Is k3s running?"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Check/create SSH tunnel
check_tunnel() {
    log_info "Checking SSH tunnel..."
    
    # Test if tunnel is active by checking from RunPod side
    if ssh gpu-test-ssh "curl -s --max-time 3 http://localhost:30500 > /dev/null" 2>&1; then
        log_success "SSH tunnel active"
        return 0
    fi
    
    log_warn "SSH tunnel not active. Starting tunnel..."
    log_info "Please run in another terminal:"
    echo "  ssh -N -R 30500:localhost:30500 -R 30900:localhost:30900 gpu-test-ssh"
    echo ""
    read -p "Press Enter when tunnel is established..."
}

# Submit training job
submit_job() {
    local job_type=$1
    local cluster_name="${2:-gpu-training}"
    
    log_info "Submitting $job_type training job..."
    
    case $job_type in
        "llm"|"LLM")
            TASK_FILE="$PROJECT_ROOT/skypilot/tasks/train-llm-runpod.yaml"
            ;;
        "bert"|"BERT")
            TASK_FILE="$PROJECT_ROOT/skypilot/tasks/train-bert-runpod.yaml"
            ;;
        "test"|"TEST")
            TASK_FILE="$PROJECT_ROOT/skypilot/tasks/gpu-test-runpod-ssh.yaml"
            ;;
        *)
            log_error "Unknown job type: $job_type"
            echo "Available: llm, bert, test"
            exit 1
            ;;
    esac
    
    # Launch or reuse cluster
    log_info "Launching GPU cluster: $cluster_name"
    cd "$PROJECT_ROOT/skypilot/tasks"
    
    if sky status | grep -q "$cluster_name"; then
        log_info "Cluster exists, reusing..."
        echo "y" | sky exec "$cluster_name" "$TASK_FILE"
    else
        sky launch -c "$cluster_name" "$TASK_FILE" --yes
    fi
    
    log_success "Job submitted!"
    echo ""
    echo "Monitor with:"
    echo "  sky queue $cluster_name"
    echo "  sky logs $cluster_name"
    echo ""
    echo "View results: http://localhost:30500"
}

# Show usage
usage() {
    echo "MLOps Lab - Training Job Submission"
    echo ""
    echo "Usage: $0 <job-type> [cluster-name]"
    echo ""
    echo "Job types:"
    echo "  llm   - Fine-tune TinyLlama with LoRA"
    echo "  bert  - BERT text classification"
    echo "  test  - GPU connectivity test"
    echo ""
    echo "Examples:"
    echo "  $0 llm"
    echo "  $0 llm my-experiment"
    echo "  $0 test"
}

# Main
main() {
    if [ $# -lt 1 ]; then
        usage
        exit 1
    fi
    
    check_prereqs
    submit_job "$1" "${2:-}"
}

main "$@"
