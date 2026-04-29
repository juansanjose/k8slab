#!/bin/bash
# create-vastai-worker.sh
# Creates a Vast.ai instance that joins as a real k8s worker node

set -euo pipefail

# Load configuration
if [[ -f ~/.vastai/worker-config.env ]]; then
    source ~/.vastai/worker-config.env
fi

# Required environment variables
K3S_URL="${K3S_URL:-}"
K3S_TOKEN="${K3S_TOKEN:-}"
TS_AUTHKEY="${TS_AUTHKEY:-}"
VASTAI_KEY="${VASTAI_KEY:-}"

# GPU preferences
GPU_NAME="${GPU_NAME:-RTX 4090}"
MAX_DPH="${MAX_DPH:-0.50}"
DISK_GB="${DISK_GB:-30}"
IMAGE="${IMAGE:-ubuntu:22.04}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $*"; }
die() { error "$*"; exit 1; }

# Validate
[[ -z "$VASTAI_KEY" ]] && die "VASTAI_KEY not set"
[[ -z "$K3S_URL" ]] && die "K3S_URL not set. Run setup-k3s-server-for-workers.sh first"
[[ -z "$K3S_TOKEN" ]] && die "K3S_TOKEN not set"
[[ -z "$TS_AUTHKEY" ]] && die "TS_AUTHKEY not set"

log "=== Creating Vast.ai Worker Node ==="
log "GPU: $GPU_NAME"
log "Max Price: \$${MAX_DPH}/hr"
log "Disk: ${DISK_GB}GB"
log ""

# Create onstart script that sets up the worker
ONSTART_SCRIPT=$(cat <> 'ONSTARTEOF'
#!/bin/bash
set -e

# Install dependencies
apt-get update -qq && apt-get install -y -qq curl ca-certificates socat proxychains4

# Download and run worker setup
curl -fsSL https://raw.githubusercontent.com/juansanjose/k8slab/main/scripts/vastai-worker-setup.sh -o /tmp/worker-setup.sh
chmod +x /tmp/worker-setup.sh

export K3S_URL="$K3S_URL"
export K3S_TOKEN="$K3S_TOKEN"
export TS_AUTHKEY="$TS_AUTHKEY"
export NODE_NAME="vastai-worker-$(date +%s)"

exec /tmp/worker-setup.sh
ONSTARTEOF
)

# Search for GPU offers
log "Searching for GPU offers..."
SEARCH_RESULT=$(curl -s -H "Authorization: Bearer ${VASTAI_KEY}" \
    "https://console.vast.ai/api/v0/bundles/?q=%7B%7D")

# Extract offer IDs (this is simplified - you may want better filtering)
OFFER_ID=$(echo "$SEARCH_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
offers = data.get('offers', [])
for offer in offers:
    if '${GPU_NAME}' in offer.get('gpu_name', ''):
        if offer.get('dph_total', 999) <= ${MAX_DPH}:
            print(offer['id'])
            break
" 2>/dev/null || true)

if [[ -z "$OFFER_ID" ]]; then
    log "No offers found for ${GPU_NAME} under \$${MAX_DPH}/hr"
    log "Trying cheapest available GPU..."
    OFFER_ID=$(echo "$SEARCH_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
offers = data.get('offers', [])
if offers:
    print(offers[0]['id'])
" 2>/dev/null || true)
fi

[[ -z "$OFFER_ID" ]] && die "No suitable GPU offers found"

log "Selected offer ID: $OFFER_ID"

# Create instance
log "Creating instance..."
CREATE_RESULT=$(curl -s -X PUT \
    -H "Authorization: Bearer ${VASTAI_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
        \"client_id\": \"k8s-worker\",
        \"image\": \"${IMAGE}\",
        \"env\": {
            \"K3S_URL\": \"${K3S_URL}\",
            \"K3S_TOKEN\": \"${K3S_TOKEN}\",
            \"TS_AUTHKEY\": \"${TS_AUTHKEY}\"
        },
        \"onstart\": $(echo "$ONSTART_SCRIPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
        \"disk\": ${DISK_GB}
    }" \
    "https://console.vast.ai/api/v0/asks/${OFFER_ID}/")

# Check result
if echo "$CREATE_RESULT" | grep -q '"success":true'; then
    INSTANCE_ID=$(echo "$CREATE_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['instance_id'])" 2>/dev/null || true)
    log "Instance created successfully!"
    log "Instance ID: ${INSTANCE_ID:-unknown}"
    log ""
    log "The node should join your cluster within 2-3 minutes."
    log "Check with: kubectl get nodes -w"
else
    error "Failed to create instance"
    echo "$CREATE_RESULT" | python3 -m json.tool 2>/dev/null || echo "$CREATE_RESULT"
    exit 1
fi