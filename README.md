# Hybrid MLOps Lab

**Kubernetes Control Plane + SkyPilot GPU Compute**

A production-ready MLOps environment that keeps infrastructure services on your local k3s cluster while offloading GPU training to RunPod via SkyPilot.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes (k3s) - Control Plane             │
│  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌──────────┐            │
│  │ Kubeflow │ │  MLflow  │ │ MinIO  │ │ Jupyter  │            │
│  │Pipelines │ │Tracking  │ │Storage │ │  Hub     │            │
│  └────┬─────┘ └────┬─────┘ └───┬────┘ └────┬─────┘            │
│       └─────────────┴───────────┴───────────┘                  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  SkyPilot submits GPU jobs to RunPod from k3s pods       │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────────────┬───────────────────────────────┘
                                   │
                    SkyPilot API   │  RunPod SDK
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                         RunPod Cloud                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐   │
│  │ GPU Instance    │  │ GPU Instance    │  │ GPU Instance │   │
│  │ (RTX 4090)      │  │ (A100)          │  │ (RTX 3090)   │   │
│  │ Training Job 1  │  │ Training Job 2  │  │ Inference    │   │
│  └─────────────────┘  └─────────────────┘  └──────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# 1. Verify everything is ready
make setup

# 2. Test GPU connectivity on RunPod (~$0.01)
make gpu-test

# 3. Run LLM training (~$0.44/hr for RTX 4090)
make train-llm

# 4. Check results
make status
```

## Backend: RunPod (Recommended)

**RunPod** is the primary GPU backend. It works out-of-the-box with SkyPilot and is more reliable than alternatives.

**Why RunPod?**
- ✅ Works with SkyPilot immediately
- ✅ No SDK compatibility issues
- ✅ Better network connectivity
- ✅ More reliable infrastructure

**Pricing:** RTX 4090 ~$0.44/hr, RTX 3090 ~$0.25/hr

**Setup:** See [docs/runpod-setup.md](docs/runpod-setup.md)

## Services

| Service | Purpose | URL | Status |
|---------|---------|-----|--------|
| **MLflow** | Experiment tracking | http://localhost:30500 | Running |
| **MinIO** | S3-compatible storage | http://localhost:30901 | Running |
| **JupyterHub** | Notebooks | http://localhost:30800 | Running |
| **TensorBoard** | Visualization | http://localhost:30606 | Running |
| **Kubeflow** | ML pipelines | Cluster internal | Running |

## Project Structure

```
mlops-lab/
├── base/                    # Kubernetes manifests
│   ├── postgres.yaml        # Metadata database
│   ├── minio.yaml           # Object storage
│   ├── mlflow.yaml          # Experiment tracking
│   ├── jupyterhub.yaml      # Notebooks
│   └── kubeflow/            # Pipeline engine
│
├── skypilot/                # GPU compute tasks
│   ├── tasks/               # Task definitions
│   │   ├── gpu-test-runpod.yaml       # RunPod GPU test
│   │   ├── train-llm-runpod.yaml      # RunPod LLM training
│   │   ├── train-bert-runpod.yaml     # RunPod BERT training
│   │   ├── gpu-test.yaml              # Vast.ai GPU test (needs fixes)
│   │   ├── train-llm.yaml             # Vast.ai LLM training (needs fixes)
│   │   └── train-bert.yaml            # Vast.ai BERT training (needs fixes)
│   │
│   ├── scripts/             # Helper utilities
│   │   ├── skypilot-helpers.sh  # Bash aliases
│   │   └── cost-tracker.py      # Spending tracker
│   │
│   └── pipelines/           # Kubeflow integration
│       └── kfp-skypilot.py  # Pipeline with GPU steps
│
├── training/                # Training scripts and guides
├── examples/                # Working examples
│   ├── 01-gpu-test.sh
│   ├── 02-mlflow-logging.sh
│   └── 03-full-pipeline.sh
│
└── docs/                    # Documentation
    ├── ARCHITECTURE.md      # Detailed architecture
    ├── skypilot-guide.md    # SkyPilot usage guide
    ├── runpod-setup.md      # RunPod setup guide
    ├── cost-optimization.md # Cost saving strategies
    ├── troubleshooting.md   # Common issues
    └── VASTAI_PR_DOCUMENTATION.md  # Vast.ai PR docs
```

## Commands

```bash
# GPU Tasks (RunPod backend)
make gpu-test           # Test GPU (~$0.01, 2-5 min)
make train-llm          # LLM fine-tuning
make train-bert         # BERT classification

# Monitoring
make status             # Clusters and services
make costs              # Track spending
make services           # Health check

# Utilities
source mlops-lab/skypilot/scripts/skypilot-helpers.sh
skypilot-help           # Show all helper commands
```

## Vast.ai (Alternative Backend)

**Status:** Requires PR fixes to work with SkyPilot 0.12.1+

Vast.ai tasks exist in the codebase but have SDK compatibility issues:
- `api_key_access` AttributeError
- Unsupported `direct` parameter
- Incorrect `ssh` parameter
- Wrong `env` parameter type

**PR Submitted:** https://github.com/skypilot-org/skypilot/pull/9487

**Documentation:** See [docs/VASTAI_PR_DOCUMENTATION.md](docs/VASTAI_PR_DOCUMENTATION.md)

**Workaround:** Use RunPod backend for now, or use Vast.ai CLI directly:
```bash
vastai search offers 'gpu_name=="RTX 4090"' -o dph
vastai create instance <id> --image pytorch/pytorch --disk 10 --ssh
```

## Cost Model

| Component | Cost | Notes |
|-----------|------|-------|
| **k3s cluster** (laptop) | $0 | Your hardware |
| **MLflow, MinIO, etc.** | $0 | Runs locally |
| **RunPod GPU** | $0.25-2.49/hr | Only when training |
| **Typical training run** | ~$0.15-1.00 | 30min-2hr session |

## Next Steps

1. Run `make gpu-test` to verify RunPod works
2. Try `make train-llm` for first real training job
3. Check MLflow UI to see logged metrics
4. Explore Kubeflow integration in `skypilot/pipelines/`
5. Set up cost alerts with `cost-tracker.py`

## Documentation

- [RunPod Setup](docs/runpod-setup.md) - Configure RunPod backend
- [Architecture Details](docs/ARCHITECTURE.md) - System design
- [SkyPilot Guide](docs/skypilot-guide.md) - How to use SkyPilot
- [Cost Optimization](docs/cost-optimization.md) - Keep costs low
- [Troubleshooting](docs/troubleshooting.md) - Common issues
- [Vast.ai PR](docs/VASTAI_PR_DOCUMENTATION.md) - Vast.ai fix documentation

---

**Status:** All control plane services running. RunPod backend ready for GPU training jobs.