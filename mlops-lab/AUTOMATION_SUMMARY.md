# MLOps Lab - Automation Summary

## What Was Built

### 1. Containerized Training Environment
- **Dockerfile** (`mlops-lab/Dockerfile`)
  - PyTorch 2.3.0 with CUDA 12.1
  - All ML packages pre-installed
  - No runtime pip installs needed
  - Consistent environment across runs

### 2. Kubernetes-Native Resources
- **ConfigMaps** (`k8s/configs.yaml`)
  - Training hyperparameters
  - SkyPilot configuration
  - Environment settings
- **Secrets** (`k8s/configs.yaml`)
  - API keys (RunPod, MinIO)
  - Database credentials
  - Secure storage in k8s
- **Job Templates** (`k8s/training-job.yaml`)
  - Kubernetes Jobs for training
  - Persistent volumes for models
  - GPU resource requests

### 3. Automation Scripts
- **`scripts/setup.sh`** - One-command setup
  - Installs k3s automatically
  - Deploys all MLOps services
  - Configures SkyPilot
  - Sets up SSH tunnel service
  - **Requires: sudo**

- **`scripts/train.sh`** - Easy training submission
  - Abstracts SkyPilot commands
  - Automatic tunnel management
  - Job type selection (llm, bert, test)

- **`scripts/cloud-native.sh`** - Container orchestration
  - Build/push containers
  - Deploy k8s resources
  - Run cloud training
  - Health checks
  - Cleanup

- **`scripts/tunnel.sh`** - SSH tunnel automation
  - Start/stop/status tunnels
  - Systemd service installation
  - Connectivity checks

- **`scripts/check-env.sh`** - Environment validation
  - Checks all prerequisites
  - Service accessibility tests
  - Clear pass/fail summary

### 4. Makefile Commands
```bash
make setup      # Full automated setup (sudo)
make build      # Build training container
make deploy     # Deploy to Kubernetes
make train      # Submit LLM training
make status     # Check everything
make cleanup    # Remove cloud resources
make local-dev  # Start local Docker stack
```

### 5. Docker Compose Stack
- **docker-compose.yaml**
  - Local MLflow for development
  - PostgreSQL database
  - MinIO object storage
  - GPU trainer container
  - No cloud needed for testing

## Architecture

```
User
 │
 ├─► make setup (sudo)
 │   ├─► Install k3s
 │   ├─► Deploy MLflow/MinIO/Postgres
 │   ├─► Install SkyPilot
 │   └─► Configure everything
 │
 ├─► make train
 │   ├─► Build container (if needed)
 │   ├─► Launch RunPod GPU instance
 │   ├─► Start SSH tunnel automatically
 │   ├─► Run training in container
 │   └─► Log metrics to local MLflow
 │
 └─► make status
     └─► Check all components
```

## What Changed (vs Manual Setup)

### Before (Manual)
1. Install k3s manually
2. Deploy services one by one
3. Configure SkyPilot manually
4. Build SSH tunnel by hand
5. Write long SkyPilot commands
6. Monitor via sky logs

### After (Automated)
1. `sudo make setup` ← One command
2. `make train` ← One command
3. `make status` ← Check everything
4. Done! 🎉

## What Requires Sudo

- **k3s installation** (system service)
- **kubeconfig permissions** (/etc/rancher/k3s/k3s.yaml)
- **Systemd service creation** (SSH tunnel)
- **Docker registry setup** (optional)

Everything else runs as regular user.

## Quick Start

### Fresh Install
```bash
cd /home/juan/k8s/mlops-lab
sudo make setup
make train
```

### Check Status
```bash
make status
```

### View Results
```bash
make mlflow  # Opens browser
```

### Cleanup
```bash
make cleanup  # Removes cloud resources
```

## Cloud-Native Features

- **ConfigMaps**: Training config as code
- **Secrets**: Secure credential management
- **Jobs**: Batch training workloads
- **PVCs**: Persistent model storage
- **Services**: Internal networking
- **Containers**: Immutable training environment

## Next Steps

1. **Run environment check**
   ```bash
   ./scripts/check-env.sh
   ```

2. **Build container**
   ```bash
   make build
   ```

3. **Test training**
   ```bash
   make train
   ```

4. **Monitor in MLflow**
   ```bash
   # Opens http://localhost:30500
   make mlflow
   ```

## Files Created

```
mlops-lab/
├── Dockerfile                    ← Container definition
├── docker-compose.yaml           ← Local dev stack
├── Makefile                      ← Easy commands
├── README.md                     ← Documentation
├── k8s/
│   ├── configs.yaml             ← ConfigMaps + Secrets
│   └── training-job.yaml        ← K8s Job template
└── scripts/
    ├── setup.sh                 ← One-command setup
    ├── train.sh                 ← Training submission
    ├── cloud-native.sh          ← Container orchestration
    ├── tunnel.sh                ← SSH tunnel manager
    └── check-env.sh             ← Environment checker
```

## Enterprise Readiness

✅ Containerized workloads
✅ Kubernetes-native resources
✅ Infrastructure as Code
✅ Automated setup
✅ Secret management
✅ Persistent storage
✅ Centralized logging
✅ Resource abstraction
✅ Cloud-agnostic (RunPod, AWS, GCP, Azure)
✅ Cost optimization (pay only for GPU time)

## Support Commands

```bash
# Full setup
sudo ./scripts/setup.sh

# Just check environment
./scripts/check-env.sh

# Manual tunnel control
./scripts/tunnel.sh start
./scripts/tunnel.sh status
./scripts/tunnel.sh stop

# Submit training manually
./scripts/train.sh llm
./scripts/train.sh bert
./scripts/train.sh test

# Container operations
./scripts/cloud-native.sh build
./scripts/cloud-native.sh deploy
./scripts/cloud-native.sh run llm
./scripts/cloud-native.sh health
./scripts/cloud-native.sh cleanup
```

Everything is now automated and cloud-native! 🚀
