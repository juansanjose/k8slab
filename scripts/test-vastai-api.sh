#!/bin/bash
# test-vastai-api.sh
# Test different Vast.ai API parameters to find what works

set -e

API_KEY="${VASTAI_KEY:-YOUR_VASTAI_API_KEY}"
BASE_URL="https://console.vast.ai/api/v0"

echo "=== Testing Vast.ai API ==="
echo ""

# 1. Search for offers
echo "[1/3] Searching for GPU offers..."
SEARCH_RESULT=$(curl -s -H "Authorization: Bearer ${API_KEY}" "${BASE_URL}/bundles/?q=%7B%7D")

# Get first offer ID
OFFER_ID=$(echo "$SEARCH_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
offers = data.get('offers', [])
if offers:
    print(offers[0]['id'])
" 2>/dev/null || true)

if [[ -z "$OFFER_ID" ]]; then
    echo "ERROR: No offers found"
    exit 1
fi

echo "Found offer ID: $OFFER_ID"
echo ""

# 2. Test different create parameters
echo "[2/3] Testing instance creation with different parameters..."

# Test 1: Minimal payload
echo "Test 1: Minimal payload (just image + runtype)..."
RESULT1=$(curl -s -X PUT \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "client_id": "test",
        "image": "ubuntu:22.04",
        "image_runtype": "ssh",
        "gpu_count": 1
    }' \
    "${BASE_URL}/asks/${OFFER_ID}/")

echo "Response: $(echo "$RESULT1" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("Success:", d.get("success"), "Error:", d.get("error", "none"))' 2>/dev/null || echo "$RESULT1")"
echo ""

# Test 2: With onstart script
echo "Test 2: With onstart script..."
RESULT2=$(curl -s -X PUT \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "client_id": "test",
        "image": "ubuntu:22.04",
        "image_runtype": "ssh",
        "gpu_count": 1,
        "onstart": "#!/bin/bash\necho Hello from GPU container"
    }' \
    "${BASE_URL}/asks/${OFFER_ID}/")

echo "Response: $(echo "$RESULT2" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("Success:", d.get("success"), "Error:", d.get("error", "none"))' 2>/dev/null || echo "$RESULT2")"
echo ""

# Test 3: With env vars
echo "Test 3: With environment variables..."
RESULT3=$(curl -s -X PUT \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "client_id": "test",
        "image": "nvidia/cuda:12.0-base",
        "image_runtype": "ssh",
        "gpu_count": 1,
        "env": ["TEST_VAR=hello"]
    }' \
    "${BASE_URL}/asks/${OFFER_ID}/")

echo "Response: $(echo "$RESULT3" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("Success:", d.get("success"), "Error:", d.get("error", "none"))' 2>/dev/null || echo "$RESULT3")"
echo ""

# 3. Check instances
echo "[3/3] Checking created instances..."
sleep 2
INSTANCES=$(curl -s -H "Authorization: Bearer ${API_KEY}" "${BASE_URL}/instances/")
echo "Active instances:"
echo "$INSTANCES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for inst in data.get('instances', []):
    print(f\"  ID: {inst['id']}, Status: {inst.get('actual_status', 'unknown')}, GPU: {inst.get('gpu_name', 'none')}\")
" 2>/dev/null || echo "No instances"

echo ""
echo "=== Test Complete ==="
echo ""
echo "Check which test succeeded and use those parameters."