#!/bin/bash

# MLOps Lab - Environment Checker
# Validates that all components are properly configured

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN++))
}

echo "========================================"
echo "  MLOps Lab - Environment Check"
echo "========================================"
echo ""

# Check k3s
echo -e "${BLUE}Kubernetes (k3s)${NC}"
if command -v k3s > /dev/null 2>&1; then
    if kubectl get nodes > /dev/null 2>&1; then
        check_pass "k3s is installed and running"
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        echo "  Nodes: $NODE_COUNT"
    else
        check_fail "k3s installed but not accessible (try: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml)"
    fi
else
    check_fail "k3s not installed"
fi
echo ""

# Check MLOps services
echo -e "${BLUE}MLOps Services${NC}"
if kubectl get pods -n mlops > /dev/null 2>&1; then
    MLFLOW_READY=$(kubectl get pod -l app=mlflow -n mlops -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    MINIO_READY=$(kubectl get pod -l app=minio -n mlops -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    POSTGRES_READY=$(kubectl get pod -l app=postgres -n mlops -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    
    [ "$MLFLOW_READY" = "Running" ] && check_pass "MLflow is running" || check_fail "MLflow not running"
    [ "$MINIO_READY" = "Running" ] && check_pass "MinIO is running" || check_fail "MinIO not running"
    [ "$POSTGRES_READY" = "Running" ] && check_pass "PostgreSQL is running" || check_fail "PostgreSQL not running"
else
    check_fail "MLOps namespace not found"
fi
echo ""

# Check service accessibility
echo -e "${BLUE}Service Accessibility${NC}"
if curl -s --max-time 3 http://localhost:30500 > /dev/null 2>&1; then
    check_pass "MLflow accessible on localhost:30500"
else
    check_fail "MLflow not accessible on localhost:30500"
fi

if curl -s --max-time 3 http://localhost:30900/minio/health/live > /dev/null 2>&1; then
    check_pass "MinIO accessible on localhost:30900"
else
    check_fail "MinIO not accessible on localhost:30900"
fi
echo ""

# Check SkyPilot
echo -e "${BLUE}SkyPilot${NC}"
if command -v sky > /dev/null 2>&1; then
    check_pass "SkyPilot installed"
    
    # Check backends
    if sky check 2>/dev/null | grep -q "RunPod.*enabled"; then
        check_pass "RunPod backend enabled"
    else
        check_warn "RunPod backend not configured"
    fi
else
    check_fail "SkyPilot not installed"
fi
echo ""

# Check Docker
echo -e "${BLUE}Docker${NC}"
if command -v docker > /dev/null 2>&1; then
    if docker info > /dev/null 2>&1; then
        check_pass "Docker is running"
    else
        check_fail "Docker installed but not running"
    fi
else
    check_warn "Docker not installed (needed for container builds)"
fi
echo ""

# Check API keys
echo -e "${BLUE}API Keys${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/../.env"

if [ -f "$ENV_FILE" ]; then
    check_pass ".env file exists"
    
    if grep -q "RunPod_Key" "$ENV_FILE" && ! grep -q "RunPod_Key=$" "$ENV_FILE"; then
        check_pass "RunPod API key configured"
    else
        check_fail "RunPod API key not configured"
    fi
else
    check_fail ".env file not found"
fi
echo ""

# Check SSH keys for SkyPilot
echo -e "${BLUE}SSH Keys${NC}"
if [ -f ~/.ssh/sky-key ]; then
    check_pass "SkyPilot SSH key exists"
else
    check_warn "SkyPilot SSH key not found (will be created on first use)"
fi
echo ""

# Summary
echo "========================================"
echo "  Summary"
echo "========================================"
echo -e "${GREEN}Passed:${NC} $PASS"
echo -e "${RED}Failed:${NC} $FAIL"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✓ Environment is ready!${NC}"
    echo "Run 'make train' to start training"
    exit 0
else
    echo -e "${RED}✗ Environment has issues. Please fix the failures above.${NC}"
    exit 1
fi
