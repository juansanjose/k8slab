# API Key Management - How It Works

## Overview

Your API keys are managed securely through a 3-layer system:

```
┌─ Interactive Setup ─┐
│  make secrets       │
└────────┬────────────┘
         │
    ┌────▼────┐
    │ .env    │  ← Local file (never committed)
    │ file    │
    └────┬────┘
         │
    ┌────▼─────────┐
    │ Kubernetes   │  ← Encrypted in cluster
    │ Secrets      │
    └────┬─────────┘
         │
    ┌────▼──────────┐
    │ Training      │  ← Mounted as env vars
    │ Containers    │
    └───────────────┘
```

## The Three Layers

### Layer 1: Interactive Setup (`make secrets`)

**What it does:**
- Walks you through entering API keys interactively
- Validates key format (e.g., RunPod keys start with `rpa_`)
- Creates the `.env` file with proper permissions

**Example session:**
```bash
$ make secrets

╔══════════════════════════════════════════════╗
║         MLOps Lab - Secrets Setup            ║
╚══════════════════════════════════════════════╝

[Step 1/3] RunPod API Key (Required)

RunPod provides GPU instances for training.
Get your API key from:
  https://www.runpod.io/console/user/settings

Paste your RunPod API Key: rpa_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

[Step 2/3] Optional Keys (Press Enter to skip)

Vast.ai API Key (backup GPU provider)
Paste Vast.ai Key (or Enter to skip): 

Tailscale Auth Key (VPN for networking)
Paste Tailscale Key (or Enter to skip): 

[Step 3/3] Creating Secrets File
✓ Secrets file created: /home/juan/k8s/.env
ℹ File permissions set to 600 (readable only by you)

ℹ Syncing secrets to Kubernetes...
✓ Secrets synced to Kubernetes cluster

╔══════════════════════════════════════════════╗
║         Secrets Setup Complete!              ║
╚══════════════════════════════════════════════╝
```

### Layer 2: Local `.env` File

**Location:** `/home/juan/k8s/.env`

**What it contains:**
```bash
RunPod_Key=rpa_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
VASTAI_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TS_AUTHKEY=tskey-auth-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Security:**
- File permissions: `600` (only readable by owner)
- Listed in `.gitignore` (never committed)
- Stored outside container/k8s (on host filesystem)

**Who reads it:**
- **SkyPilot** - Uses `RunPod_Key` to provision GPU instances
- **Scripts** - `./scripts/keys.sh sync` copies it to Kubernetes

### Layer 3: Kubernetes Secrets

**Command to view:**
```bash
kubectl get secret cloud-credentials -n mlops -o yaml
```

**What's stored:**
```yaml
data:
  runpod-api-key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  # base64 encoded
  minio-access-key: bWluaW9hZG1pbg==
  minio-secret-key: bWluaW9hZG1pbjEyMw==
```

**Who uses it:**
- **Training pods** - Mount secrets as environment variables
- **MLflow** - Reads MinIO credentials for artifact storage

## How Keys Flow During Training

### Step-by-step:

1. **You run:** `make train`

2. **SkyPilot reads** `.env` file:
   ```python
   # SkyPilot automatically finds RunPod_Key in .env
   # Uses it to authenticate with RunPod API
   ```

3. **SkyPilot provisions** GPU instance on RunPod:
   ```
   POST https://api.runpod.io/graphql
    Authorization: Bearer rpa_xxxxxxxxxxxxxxxxxxxx...
   ```

4. **SSH Tunnel starts** automatically:
   ```bash
   ssh -N -R 30500:localhost:30500 gpu-training
   ```

5. **Training container starts** with K8s secrets:
   ```yaml
   env:
     - name: MLFLOW_TRACKING_URI
       value: "http://localhost:30500"
     - name: AWS_ACCESS_KEY_ID
       valueFrom:
         secretKeyRef:
           name: cloud-credentials
           key: minio-access-key
   ```

6. **Training runs** and logs to MLflow via tunnel

## Commands

### Check current keys
```bash
make secrets
# Select option 2: View current values
```

### Update a specific key
```bash
make secrets
# Select option 4: Update specific keys
# Choose: 1. RunPod API Key
```

### Sync to Kubernetes
```bash
./mlops-lab/scripts/keys.sh sync
```

### Check status
```bash
./mlops-lab/scripts/keys.sh status
```

## Security Best Practices

1. **Never commit `.env`**
   - Already in `.gitignore`
   - Keys would be exposed in git history

2. **File permissions**
   ```bash
   chmod 600 .env
   ```

3. **Rotate keys regularly**
   ```bash
   make secrets
   # Select option 4 → Update specific keys
   ```

4. **Backup before rotation**
   ```bash
   cp .env .env.backup
   ```

5. **Use environment-specific keys**
   - Development: Use separate RunPod account
   - Production: Restricted keys with limited access

## Troubleshooting

### "RunPod API key not configured"
```bash
make secrets
# Enter your RunPod API key
```

### "Secrets not synced to Kubernetes"
```bash
./mlops-lab/scripts/keys.sh sync
```

### "SkyPilot can't find keys"
- Ensure `.env` is in project root (`/home/juan/k8s/.env`)
- Check that `RunPod_Key` variable name is correct
- Restart shell session after editing `.env`

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│  HOST MACHINE                                               │
│  ┌─────────────────┐                                       │
│  │ ~/.env          │ ← Interactive setup creates this      │
│  │ (chmod 600)     │                                       │
│  └────────┬────────┘                                       │
│           │                                                 │
│  ┌────────▼────────┐                                       │
│  │ make secrets    │ ← Interactive wizard                  │
│  └────────┬────────┘                                       │
│           │                                                 │
│  ┌────────▼────────┐                                       │
│  │ scripts/keys.sh │ ← Syncs to Kubernetes                 │
│  └────────┬────────┘                                       │
│           │                                                 │
└───────────┼────────────────────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────────────────────┐
│  KUBERNETES (k3s)                                           │
│  ┌──────────────────────┐                                  │
│  │ Secret:              │                                  │
│  │ cloud-credentials    │ ← Base64 encoded                  │
│  │  - runpod-api-key    │                                  │
│  │  - minio-access-key  │                                  │
│  └──────────┬───────────┘                                  │
│             │                                               │
│  ┌──────────▼───────────┐                                  │
│  │ Training Pod         │ ← Mounts secrets as env vars     │
│  │  - MLFLOW_TRACKING_URI                                   │
│  │  - AWS_ACCESS_KEY_ID  ← From secret                      │
│  └──────────────────────┘                                  │
└────────────────────────────────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────────────────────┐
│  CLOUD (RunPod)                                             │
│  ┌──────────────────────┐                                  │
│  │ GPU Instance         │ ← SkyPilot provisions using      │
│  │  - SSH tunnel to host  .env RunPod_Key                   │
│  │  - Training container                                    │
│  └──────────────────────┘                                  │
└────────────────────────────────────────────────────────────┘
```

## Summary

| Component | Stores Keys | Used By | Security |
|-----------|-------------|---------|----------|
| `.env` file | RunPod, Vast.ai, Tailscale | SkyPilot, scripts | `chmod 600`, `.gitignore` |
| K8s Secrets | All keys (base64) | Training pods | Encrypted at rest |
| Environment | Runtime values | Training code | In-memory only |

**Bottom line:** Run `make secrets` once, and everything else works automatically!
