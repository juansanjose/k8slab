#!/bin/bash

# MLOps Lab - Interactive Secrets Setup
# Walks the user through creating the .env file with API keys

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PARENT_ROOT="$(dirname "$PROJECT_ROOT")"
ENV_FILE="$PARENT_ROOT/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         MLOps Lab - Secrets Setup            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[Step $1/3]${NC} $2"
    echo ""
}

print_info() {
    echo -e "${CYAN}ℹ${NC}  $1"
}

print_success() {
    echo -e "${GREEN}✓${NC}  $1"
}

print_error() {
    echo -e "${RED}✗${NC}  $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

# Check if .env already exists
check_existing() {
    if [ -f "$ENV_FILE" ]; then
        echo ""
        print_warn "A secrets file already exists!"
        echo ""
        echo "Location: $ENV_FILE"
        echo ""
        echo -e "${YELLOW}Options:${NC}"
        echo "  1. Keep existing (skip)"
        echo "  2. View current values"
        echo "  3. Overwrite with new values"
        echo "  4. Update specific keys"
        echo ""
        read -p "Select option [1-4]: " choice
        
        case $choice in
            1)
                echo ""
                print_success "Keeping existing secrets file"
                return 1
                ;;
            2)
                echo ""
                echo -e "${CYAN}Current values:${NC}"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                while IFS= read -r line; do
                    if [[ $line =~ ^#.*$ ]] || [[ -z $line ]]; then
                        echo "$line"
                    else
                        key="${line%%=*}"
                        value="${line#*=}"
                        if [ ${#value} -gt 20 ]; then
                            echo "$key=${value:0:20}..."
                        else
                            echo "$line"
                        fi
                    fi
                done < "$ENV_FILE"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                read -p "Press Enter to continue..."
                return 1
                ;;
            3)
                echo ""
                print_warn "This will overwrite all existing keys!"
                read -p "Are you sure? [y/N]: " confirm
                if [[ ! $confirm =~ ^[Yy]$ ]]; then
                    echo "Cancelled."
                    return 1
                fi
                return 0
                ;;
            4)
                echo ""
                update_specific_keys
                return 1
                ;;
            *)
                echo "Invalid option. Keeping existing."
                return 1
                ;;
        esac
    fi
    return 0
}

# Update specific keys
update_specific_keys() {
    set -a
    source "$ENV_FILE"
    set +a
    
    echo "Which key would you like to update?"
    echo ""
    echo "  1. RunPod API Key (required for GPU training)"
    echo "  2. Vast.ai API Key (optional backup GPU)"
    echo "  3. Tailscale Auth Key (optional VPN)"
    echo "  4. K3s Token (usually auto-detected)"
    echo ""
    read -p "Select [1-4]: " key_choice
    
    case $key_choice in
        1)
            read -p "Enter RunPod API Key: " new_val
            sed -i "s/^RunPod_Key=.*/RunPod_Key=$new_val/" "$ENV_FILE"
            print_success "RunPod key updated"
            ;;
        2)
            read -p "Enter Vast.ai API Key: " new_val
            sed -i "s/^VASTAI_KEY=.*/VASTAI_KEY=$new_val/" "$ENV_FILE"
            print_success "Vast.ai key updated"
            ;;
        3)
            read -p "Enter Tailscale Auth Key: " new_val
            sed -i "s/^TS_AUTHKEY=.*/TS_AUTHKEY=$new_val/" "$ENV_FILE"
            print_success "Tailscale key updated"
            ;;
        4)
            read -p "Enter K3s Token: " new_val
            sed -i "s/^K3S_TOKEN=.*/K3S_TOKEN=$new_val/" "$ENV_FILE"
            print_success "K3s token updated"
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    # Sync to K8s
    echo ""
    print_info "Syncing to Kubernetes..."
    "$SCRIPT_DIR/keys.sh" sync > /dev/null 2>&1
    print_success "Secrets synced to Kubernetes"
}

# Get RunPod key
get_runpod_key() {
    local key=""
    
    echo "─────────────────────────────────────────"
    print_step "1" "RunPod API Key (Required)"
    echo ""
    echo "RunPod provides GPU instances for training."
    echo "Get your API key from:"
    echo -e "  ${CYAN}https://www.runpod.io/console/user/settings${NC}"
    echo ""
    echo "The key looks like: rpa_XXXXXXXXXXXXXXXXXXXXXXXX"
    echo ""
    
    while [ -z "$key" ]; do
        read -p "Paste your RunPod API Key: " key
        
        if [ -z "$key" ]; then
            print_error "RunPod key is required for GPU training"
            echo ""
            read -p "Continue without GPU support? [y/N]: " skip
            if [[ $skip =~ ^[Yy]$ ]]; then
                print_warn "Skipping RunPod (you can add it later with: make secrets)"
                key="SKIPPED"
            fi
        elif [[ ! $key =~ ^rpa_[a-zA-Z0-9]{32,}$ ]]; then
            print_warn "This doesn't look like a valid RunPod key"
            print_info "Expected format: rpa_XXXXXXXXXXXXXXXXXXXXXXXX"
            echo ""
            read -p "Use anyway? [y/N]: " force
            if [[ ! $force =~ ^[Yy]$ ]]; then
                key=""
            fi
        fi
    done
    
    echo "$key"
}

# Get optional keys
get_optional_keys() {
    local keys=""
    
    echo ""
    echo "─────────────────────────────────────────"
    print_step "2" "Optional Keys (Press Enter to skip)"
    echo ""
    
    echo -e "${CYAN}Vast.ai API Key${NC} (backup GPU provider)"
    echo "  Get from: https://cloud.vast.ai/account/"
    echo "  This is optional - RunPod is the primary GPU provider"
    echo ""
    read -p "Paste Vast.ai Key (or Enter to skip): " vastai_key
    echo ""
    
    echo -e "${CYAN}Tailscale Auth Key${NC} (VPN for networking)"
    echo "  Get from: https://login.tailscale.com/admin/settings/keys"
    echo "  This is optional - SSH tunnel is the default"
    echo ""
    read -p "Paste Tailscale Key (or Enter to skip): " tailscale_key
    echo ""
    
    keys="VASTAI_KEY=$vastai_key
TS_AUTHKEY=$tailscale_key"
    
    echo "$keys"
}

# Create the .env file
create_env_file() {
    local runpod_key=$1
    local optional_keys=$2
    
    echo ""
    echo "─────────────────────────────────────────"
    print_step "3" "Creating Secrets File"
    echo ""
    
    # Backup existing if present
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Existing file backed up"
    fi
    
    cat > "$ENV_FILE" <<EOF
# MLOps Lab - Environment Secrets
# Created: $(date)
# 
# IMPORTANT: Never commit this file to git!
# It contains sensitive API keys.

# ═══════════════════════════════════════════
# REQUIRED: RunPod API Key
# Used for GPU training instances
# ═══════════════════════════════════════════
RunPod_Key=${runpod_key}

# ═══════════════════════════════════════════
# OPTIONAL: Vast.ai API Key
# Backup GPU provider
# ═══════════════════════════════════════════
${optional_keys}

# ═══════════════════════════════════════════
# K3s Configuration (auto-detected)
# Usually doesn't need to be changed
# ═══════════════════════════════════════════
K3S_TOKEN=${K3S_TOKEN:-}
EOF
    
    chmod 600 "$ENV_FILE"
    print_success "Secrets file created: $ENV_FILE"
    print_info "File permissions set to 600 (readable only by you)"
}

# Sync to Kubernetes
sync_to_k8s() {
    echo ""
    print_info "Syncing secrets to Kubernetes..."
    
    if "$SCRIPT_DIR/keys.sh" sync; then
        print_success "Secrets synced to Kubernetes cluster"
    else
        print_error "Failed to sync to Kubernetes"
        print_info "You can retry later with: make secrets"
    fi
}

# Main setup flow
main() {
    print_banner
    
    # Check if we should proceed
    if ! check_existing; then
        echo ""
        echo -e "${GREEN}Setup complete!${NC}"
        echo ""
        echo "Your secrets are ready. You can now run:"
        echo "  make train      - Start training"
        echo "  make status     - Check everything"
        echo ""
        exit 0
    fi
    
    # Get keys from user
    runpod_key=$(get_runpod_key)
    optional_keys=$(get_optional_keys)
    
    # Create file
    create_env_file "$runpod_key" "$optional_keys"
    
    # Sync
    sync_to_k8s
    
    # Final message
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Secrets Setup Complete!              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo "What's next:"
    echo "  ${CYAN}make train${NC}      - Start training on GPU"
    echo "  ${CYAN}make status${NC}     - Check all services"
    echo "  ${CYAN}make mlflow${NC}     - Open MLflow UI"
    echo ""
    echo "To update keys later:"
    echo "  ${CYAN}make secrets${NC}    - Run this again"
    echo ""
    
    if [ "$runpod_key" = "SKIPPED" ]; then
        print_warn "You skipped RunPod - GPU training won't work"
        echo "Run 'make secrets' to add it later"
    fi
}

main "$@"
