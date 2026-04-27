#!/usr/bin/env bash
# vastai-find-and-create.sh
# Interactive script to find, select, and create the best Vast.ai GPU instance
# for joining your local k3s cluster via Tailscale.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
K3S_URL="${K3S_URL:-}"
K3S_TOKEN="${K3S_TOKEN:-}"
MAX_DPH="${MAX_DPH:-0.50}"
MIN_COMPUTE_CAP="${MIN_COMPUTE_CAP:-700}"
SEARCH_LIMIT="${SEARCH_LIMIT:-10}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check prerequisites
echo "=== Vast.ai GPU Instance Finder ==="
echo ""

# Add common pip user install locations to PATH
export PATH="$HOME/.local/bin:$HOME/.pip/bin:$PATH"

if ! command -v vastai &> /dev/null; then
    echo -e "${RED}ERROR: vastai CLI not found.${NC}"
    echo "Install it with: pip install --user vastai"
    echo "Then set your API key: vastai set api-key YOUR_API_KEY"
    exit 1
fi

# Check if API key is set
if ! vastai show user &> /dev/null; then
    echo -e "${RED}ERROR: Vast.ai API key not configured.${NC}"
    echo "Set it with: vastai set api-key YOUR_API_KEY"
    echo "Get your key from: https://cloud.vast.ai/cli/"
    exit 1
fi

# Check k3s configuration
if [[ -z "$K3S_URL" ]]; then
    # Try to auto-detect from local k3s
    if command -v tailscale &> /dev/null; then
        TS_IP=$(tailscale ip -4 2>/dev/null || true)
        if [[ -n "$TS_IP" ]]; then
            K3S_URL="https://${TS_IP}:6443"
            echo -e "${GREEN}Auto-detected K3S_URL: $K3S_URL${NC}"
        fi
    fi
    
    if [[ -z "$K3S_URL" ]]; then
        echo -e "${RED}ERROR: K3S_URL not set.${NC}"
        echo "Please set it to your laptop's Tailscale IP:"
        echo "  export K3S_URL=https://100.x.y.z:6443"
        exit 1
    fi
fi

if [[ -z "$K3S_TOKEN" ]]; then
    # Try to auto-detect from local k3s
    if [[ -f /var/lib/rancher/k3s/server/node-token ]]; then
        K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || true)
        if [[ -n "$K3S_TOKEN" ]]; then
            echo -e "${GREEN}Auto-detected K3S_TOKEN from local k3s${NC}"
        fi
    fi
    
    if [[ -z "$K3S_TOKEN" ]]; then
        echo -e "${RED}ERROR: K3S_TOKEN not set.${NC}"
        echo "Get it from your k3s server:"
        echo "  sudo cat /var/lib/rancher/k3s/server/node-token"
        echo "Then set it:"
        echo "  export K3S_TOKEN=K10xxxxxxxxxx::server:xxxxxxxxxx"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  K3S_URL: $K3S_URL"
echo "  K3S_TOKEN: ${K3S_TOKEN:0:20}..."
echo "  Max price: \$${MAX_DPH}/hr"
echo "  Script directory: ${SCRIPT_DIR}"
echo ""

# Check if onstart script exists locally
ONSTART_SCRIPT="${SCRIPT_DIR}/vastai-onstart.sh"
if [[ ! -f "$ONSTART_SCRIPT" ]]; then
    echo -e "${YELLOW}WARNING: vastai-onstart.sh not found in ${SCRIPT_DIR}${NC}"
    echo "The instance will be created but you'll need to manually run the setup after SSH."
fi

# Search for available instances
echo "🔍 Searching for compatible GPU instances..."
echo "   (This may take a moment...)"
echo ""

# Dynamic search: any GPU with compute capability >= MIN_COMPUTE_CAP, direct SSH, sorted by price
# Using raw output for parsing
SEARCH_RESULTS=$(vastai search offers \
    "compute_cap >= ${MIN_COMPUTE_CAP} num_gpus>=1 inet_up > 0 direct_port_count > 0 dph_total <= ${MAX_DPH}" \
    -o "dph+" \
    --raw 2>/dev/null || true)

if [[ -z "$SEARCH_RESULTS" ]] || [[ "$SEARCH_RESULTS" == "[]" ]]; then
    echo -e "${YELLOW}No instances found with strict filters. Trying broader search...${NC}"
    SEARCH_RESULTS=$(vastai search offers \
        "num_gpus>=1 dph_total <= ${MAX_DPH}" \
        -o "dph+" \
        --raw 2>/dev/null || true)
fi

if [[ -z "$SEARCH_RESULTS" ]] || [[ "$SEARCH_RESULTS" == "[]" ]]; then
    echo -e "${RED}ERROR: No GPU instances available on Vast.ai right now.${NC}"
    echo "Try again later or adjust your search criteria:"
    echo "  export MAX_DPH=1.00  # Increase max price"
    exit 1
fi

# Save search results to temp file to avoid "argument list too long"
SEARCH_RESULTS_FILE=$(mktemp)
echo "$SEARCH_RESULTS" > "$SEARCH_RESULTS_FILE"

# Parse and display results
echo -e "${GREEN}Top available GPU instances (sorted by price):${NC}"
echo ""
printf "%-4s %-10s %-20s %-10s %-8s %-10s %-12s %-10s %s\n" \
    "NUM" "ID" "GPU" "VRAM" "\$/HR" "DLPerf" "CUDA" "Location" "Reliab"
printf "%-4s %-10s %-20s %-10s %-8s %-10s %-12s %-10s %s\n" \
    "----" "----------" "--------------------" "----------" "--------" "----------" "------------" "----------" "----------"

python3 - "$SEARCH_RESULTS_FILE" "$SEARCH_LIMIT" << 'PYEOF'
import json
import sys

results_file = sys.argv[1]
search_limit = int(sys.argv[2])

try:
    with open(results_file, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f'Error parsing search results: {e}')
    sys.exit(1)

if not isinstance(data, list):
    print('Unexpected response format')
    sys.exit(1)

count = 0
for i, offer in enumerate(data[:search_limit], 1):
    try:
        offer_id = offer.get('id', 'N/A')
        gpu_name = offer.get('gpu_name', 'Unknown')[:18]
        vram = offer.get('gpu_ram', 'N/A')
        if isinstance(vram, (int, float)):
            vram = f'{vram/1024:.1f}GB' if vram > 1024 else f'{vram}MB'
        dph = offer.get('dph_total', 'N/A')
        if isinstance(dph, (int, float)):
            dph = f'${dph:.3f}'
        dlperf = offer.get('dlperf', 'N/A')
        if isinstance(dlperf, (int, float)):
            dlperf = f'{dlperf:.1f}'
        cuda = offer.get('cuda_max_good', 'N/A')
        if isinstance(cuda, (int, float)):
            cuda = f'{cuda:.1f}'
        location = offer.get('geolocation', 'Unknown')[:8]
        reliability = offer.get('reliability2', offer.get('reliability', 0))
        if isinstance(reliability, (int, float)):
            reliability = f'{reliability*100:.0f}%'
        
        print(f'{i:<4} {offer_id:<10} {gpu_name:<20} {vram:<10} {dph:<8} {dlperf:<10} {cuda:<12} {location:<10} {reliability}')
        count += 1
    except Exception as e:
        continue

if count == 0:
    print('No valid offers found')
    sys.exit(1)
PYEOF

PYTHON_EXIT=$?

if [ $PYTHON_EXIT -ne 0 ]; then
    rm -f "$SEARCH_RESULTS_FILE"
    echo -e "${RED}ERROR: Failed to parse Vast.ai search results.${NC}"
    echo "Raw output (first 20 lines):"
    echo "$SEARCH_RESULTS" | head -20
    exit 1
fi

echo ""

# Ask user to select an instance
read -p "Enter the number of the instance you want to rent (or 'q' to quit): " SELECTION

if [[ "$SELECTION" == "q" ]] || [[ "$SELECTION" == "Q" ]]; then
    rm -f "$SEARCH_RESULTS_FILE"
    echo "Aborted."
    exit 0
fi

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
    rm -f "$SEARCH_RESULTS_FILE"
    echo -e "${RED}ERROR: Invalid selection.${NC}"
    exit 1
fi

# Extract the selected offer ID
SELECTED_OFFER=$(python3 - "$SEARCH_RESULTS_FILE" "$SELECTION" << 'PYEOF'
import json
import sys

results_file = sys.argv[1]
selection = int(sys.argv[2])

try:
    with open(results_file, 'r') as f:
        data = json.load(f)
    idx = selection - 1
    if 0 <= idx < len(data):
        print(data[idx].get('id', ''))
except:
    pass
PYEOF
)

rm -f "$SEARCH_RESULTS_FILE"

if [[ -z "$SELECTED_OFFER" ]]; then
    echo -e "${RED}ERROR: Could not find the selected instance.${NC}"
    exit 1
fi

# Get details of selected instance
echo ""
echo -e "${BLUE}Selected instance details:${NC}"

# We need to search again to get details, or we could have saved the data
# For simplicity, let's just show the ID and proceed
# Alternatively, we could save the full data and extract details
# Let's do a quick search for just this offer to show details
OFFER_DETAILS=$(vastai search offers "id=${SELECTED_OFFER}" --raw 2>/dev/null || true)

if [[ -n "$OFFER_DETAILS" ]] && [[ "$OFFER_DETAILS" != "[]" ]]; then
    echo "$OFFER_DETAILS" | python3 - << 'PYEOF'
import json
import sys

try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        offer = data[0]
        print(f"  ID: {offer.get('id', 'N/A')}")
        print(f"  GPU: {offer.get('gpu_name', 'Unknown')}")
        vram = offer.get('gpu_ram', 'N/A')
        if isinstance(vram, (int, float)):
            vram = f'{vram/1024:.1f} GB' if vram > 1024 else f'{vram} MB'
        print(f"  VRAM: {vram}")
        dph = offer.get('dph_total', 'N/A')
        if isinstance(dph, (int, float)):
            print(f"  Price: \${dph:.4f}/hr (\${dph*24:.2f}/day, \${dph*730:.2f}/month)")
        print(f"  Location: {offer.get('geolocation', 'Unknown')}")
        reliability = offer.get('reliability2', offer.get('reliability', 'N/A'))
        if isinstance(reliability, (int, float)):
            reliability = f'{reliability*100:.1f}%'
        print(f"  Reliability: {reliability}")
        print(f"  CUDA: {offer.get('cuda_max_good', 'N/A')}")
        print(f"  Internet: {offer.get('inet_up', 'N/A')} Mbps up / {offer.get('inet_down', 'N/A')} Mbps down")
except Exception as e:
    print(f'Error: {e}')
PYEOF
else
    echo "  ID: ${SELECTED_OFFER}"
    echo "  (Details unavailable - instance may have been rented)"
fi

echo ""
echo -e "${YELLOW}⚠️  This will create a Vast.ai instance and start billing immediately.${NC}"
read -p "Do you want to proceed? [y/N] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Build the create command
echo ""
echo "🚀 Creating instance..."

CREATE_CMD="vastai create instance ${SELECTED_OFFER}"
CREATE_CMD="${CREATE_CMD} --image ubuntu:22.04"
CREATE_CMD="${CREATE_CMD} --disk 32"
CREATE_CMD="${CREATE_CMD} --ssh"
CREATE_CMD="${CREATE_CMD} --direct"

# Set environment variables for the onstart script
CREATE_CMD="${CREATE_CMD} --env K3S_URL=${K3S_URL}"
CREATE_CMD="${CREATE_CMD} --env K3S_TOKEN=${K3S_TOKEN}"

# If we have the onstart script locally, we'll provide instructions
if [[ -f "$ONSTART_SCRIPT" ]]; then
    echo -e "${BLUE}Note: Onstart script found locally.${NC}"
    echo "The instance will be created and you'll need to either:"
    echo "  a) Run the onstart script manually after SSH, or"
    echo "  b) Upload it to the instance and set it as onstart-cmd"
    echo ""
fi

# Simple onstart command that downloads and runs the script from the repo
REPO_URL=$(git remote get-url origin 2>/dev/null | sed 's/.*github.com\///' | sed 's/\.git$//' || echo "")
if [[ -n "$REPO_URL" ]]; then
    ONSTART_CMD="bash -c 'export K3S_URL=${K3S_URL} && export K3S_TOKEN=${K3S_TOKEN} && curl -fsSL https://raw.githubusercontent.com/${REPO_URL}/main/scripts/vastai-onstart.sh | bash'"
    CREATE_CMD="${CREATE_CMD} --onstart-cmd \"${ONSTART_CMD}\""
    echo "  Using remote onstart script from GitHub"
else
    echo -e "${YELLOW}WARNING: Could not detect GitHub repo URL.${NC}"
    echo "  You'll need to run the onstart script manually after SSH."
fi

echo "  Command: ${CREATE_CMD}"
echo ""

# Execute the create command
eval "$CREATE_CMD" || {
    echo -e "${RED}ERROR: Failed to create instance.${NC}"
    echo ""
    echo "Common issues:"
    echo "  - Insufficient Vast.ai credit"
    echo "  - Instance no longer available"
    echo "  - Invalid offer ID"
    exit 1
}

echo ""
echo -e "${GREEN}✅ Instance creation initiated!${NC}"
echo ""
echo "Waiting for instance to be ready..."
echo "(This may take 1-2 minutes)"
echo ""

# Wait and poll for the instance
INSTANCE_ID=""
INSTANCE_DATA=""
for i in {1..30}; do
    sleep 5
    INSTANCE_INFO=$(vastai show instances --raw 2>/dev/null || true)
    
    if [[ -z "$INSTANCE_INFO" ]] || [[ "$INSTANCE_INFO" == "[]" ]]; then
        echo "  Waiting for instance to appear... (${i}/30)"
        continue
    fi
    
    # Save instance info to temp file
    INSTANCE_FILE=$(mktemp)
    echo "$INSTANCE_INFO" > "$INSTANCE_FILE"
    
    # Find our instance (most recently created)
    INSTANCE_DATA=$(python3 - "$INSTANCE_FILE" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    if isinstance(data, list) and len(data) > 0:
        # Get the most recent instance
        print(json.dumps(data[-1]))
except:
    pass
PYEOF
)
    
    rm -f "$INSTANCE_FILE"
    
    if [[ -n "$INSTANCE_DATA" ]]; then
        # Extract status
        STATUS_FILE=$(mktemp)
        echo "$INSTANCE_DATA" > "$STATUS_FILE"
        
        STATUS=$(python3 - "$STATUS_FILE" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    print(data.get('actual_status', 'unknown'))
except:
    print('unknown')
PYEOF
)
        
        INSTANCE_ID=$(python3 - "$STATUS_FILE" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    print(str(data.get('id', '')))
except:
    print('')
PYEOF
)
        
        rm -f "$STATUS_FILE"
        
        if [[ "$STATUS" == "running" ]]; then
            echo -e "${GREEN}✅ Instance is running!${NC}"
            echo ""
            break
        elif [[ "$STATUS" == "offline" ]] || [[ "$STATUS" == "error" ]]; then
            echo -e "${RED}❌ Instance failed to start (status: $STATUS)${NC}"
            exit 1
        fi
        
        echo "  Status: $STATUS... (${i}/30)"
    fi
done

if [[ -z "$INSTANCE_ID" ]]; then
    echo -e "${YELLOW}WARNING: Could not determine instance ID.${NC}"
    echo "Check manually with: vastai show instances"
fi

# Get connection info
if [[ -n "$INSTANCE_DATA" ]]; then
    echo -e "${GREEN}=== Instance Details ===${NC}"
    
    DETAILS_FILE=$(mktemp)
    echo "$INSTANCE_DATA" > "$DETAILS_FILE"
    
    python3 - "$DETAILS_FILE" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    print(f"Instance ID: {data.get('id', 'N/A')}")
    print(f"Status: {data.get('actual_status', 'N/A')}")
    print(f"GPU: {data.get('gpu_name', 'N/A')}")
    
    # SSH info
    ssh_host = data.get('ssh_host', 'N/A')
    ssh_port = data.get('ssh_port', 'N/A')
    if ssh_host != 'N/A' and ssh_port != 'N/A':
        print(f"SSH: ssh -p {ssh_port} root@{ssh_host}")
    
    # Direct info
    direct_port_count = data.get('direct_port_count', 0)
    if direct_port_count > 0:
        print(f"Direct ports: {direct_port_count}")
    
    # Price
    dph = data.get('dph_total', 'N/A')
    if isinstance(dph, (int, float)):
        print(f"Cost: \${dph:.4f}/hr")
except Exception as e:
    print(f'Error: {e}')
PYEOF
    
    rm -f "$DETAILS_FILE"
fi

echo ""
echo -e "${GREEN}=== Next Steps ===${NC}"

if [[ -f "$ONSTART_SCRIPT" ]]; then
    echo "1. The instance should auto-configure via onstart script"
    echo "2. If not, SSH in and run:"
    echo "     export K3S_URL=${K3S_URL}"
    echo "     export K3S_TOKEN=${K3S_TOKEN}"
    echo "     bash <(curl -fsSL https://raw.githubusercontent.com/${REPO_URL}/main/scripts/vastai-onstart.sh)"
else
    echo "1. SSH into the instance:"
    echo "     ssh -p <PORT> root@<HOST>"
    echo "2. Set environment variables and run vastai-onstart.sh manually"
fi

echo ""
echo "3. Check node joined: kubectl get nodes -o wide"
echo "4. If issues: journalctl -u k3s-agent -f (on Vast.ai instance)"
echo ""

if [[ -n "$INSTANCE_ID" ]]; then
    echo "To stop billing and destroy:"
    echo "  vastai destroy instance ${INSTANCE_ID}"
fi

echo ""
echo -e "${GREEN}Done! 🎉${NC}"
