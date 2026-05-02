# Cost Optimization Guide

## Overview

This hybrid architecture is already cost-effective, but you can optimize further:

**Current Costs**:
- Control plane (k3s): $0 (your laptop)
- MLOps services: $0 (run locally)
- GPU training: $0.02-0.50/hr (only when needed)

**Target**: $0.10-0.30 per training run (30-60 min)

## Strategies

### 1. Use Spot Instances

Save 50-70% with preemptible instances:

```yaml
resources:
  cloud: vast
  accelerators: RTX4090:1
  use_spot: true
```

**Trade-offs**:
- Instance can be terminated with 1-2 min warning
- Save checkpoints frequently
- Use managed jobs for automatic retry

### 2. Right-Size Your GPU

Choose GPU based on workload:

| Workload | Recommended GPU | Cost/hr | Speed |
|----------|----------------|---------|-------|
| **Development/Testing** | RTX 3090 | $0.02-0.05 | Fast enough |
| **Small models (<1B)** | RTX 4090 | $0.15-0.30 | Good |
| **Medium models (1-7B)** | A100 40GB | $0.50-1.00 | Fast |
| **Large models (7B+)** | A100 80GB | $1.00-2.00 | Required |
| **Inference** | T4 | $0.02-0.10 | Efficient |

### 3. Minimize Disk Size

```yaml
resources:
  disk_size: 20  # Instead of 50-100
```

Only store what you need:
- Datasets: Mount from MinIO (don't duplicate)
- Models: Save to MinIO, delete local copy
- Cache: Set `HF_HOME` to limited size

### 4. Use Auto-shutdown

Never pay for idle time:

```bash
# Auto-stop after 30 minutes idle
sky autostop my-cluster -i 30

# For one-off jobs, use --down
sky launch task.yaml -c myjob --down
```

### 5. Batch Multiple Jobs

Run multiple experiments on same instance:

```bash
# Launch instance
sky launch task.yaml -c shared-gpu --idle-minutes-to-autostop 60

# Run multiple experiments
sky exec shared-gpu 'python train.py --lr 1e-4'
sky exec shared-gpu 'python train.py --lr 2e-4'
sky exec shared-gpu 'python train.py --lr 5e-4'

# Terminate when done
sky down shared-gpu
```

### 6. Use Cheapest Available

Let SkyPilot find the best price:

```bash
# Don't specify exact GPU
sky launch task.yaml  # SkyPilot picks cheapest

# Or specify multiple options
sky launch task.yaml --gpus [RTX4090,RTX3090,A4000]
```

### 7. Monitor Costs

Track every run:

```bash
# Manual tracking
python skypilot/scripts/cost-tracker.py log myjob RTX4090 0.25 1.5

# View summary
python skypilot/scripts/cost-tracker.py
```

**Output**:
```
Cluster              GPU             Rate       Hours      Cost       Date
================================================================================
llm-train            RTX4090         $0.2500    1.50       $0.3750    2024-01-15
bert-train           RTX4090         $0.2200    0.75       $0.1650    2024-01-15
================================================================================
Total Spent: $0.5400
Total Runs: 2
```

### 8. Local Development First

Test everything locally before using GPU:

```bash
# Test on CPU (k3s)
sky launch task.yaml --cloud kubernetes --gpus 0

# Then scale to GPU
sky launch task.yaml --cloud vast --gpus RTX4090:1
```

### 9. Use Gradient Checkpointing

Trade compute for memory:

```python
# In training script
model.gradient_checkpointing_enable()
```

Allows larger models on cheaper GPUs.

### 10. Mixed Precision

Use FP16/FP8 to speed up training:

```python
# In training arguments
training_args = TrainingArguments(
    fp16=True,      # Half precision
    # or
    bf16=True,      # Brain float (better on A100+)
)
```

## Cost Examples

### TinyLlama Fine-tuning (1 epoch)

**Without optimization**:
- GPU: RTX 4090 @ $0.30/hr
- Time: 2 hours
- Cost: $0.60

**With optimization**:
- GPU: RTX 3090 (spot) @ $0.08/hr
- Time: 2.5 hours (slightly slower)
- Disk: 20GB
- Cost: $0.20

**Savings: 67%**

### BERT Classification

**Without optimization**:
- GPU: RTX 4090 @ $0.30/hr
- Time: 45 min
- Cost: $0.23

**With optimization**:
- GPU: RTX 3090 @ $0.05/hr
- Time: 1 hour
- Auto-shutdown: enabled
- Cost: $0.05

**Savings: 78%**

## Budget Alerts

Set spending limits:

```bash
# Check current spend
sky status --all

# Set daily limit (manual)
# Add to your training script:
python -c "
import json
from pathlib import Path

COST_LOG = Path.home() / '.skypilot_costs.json'
costs = json.loads(COST_LOG.read_text())

if costs['total_spent'] > 10.0:  # $10 limit
    print('WARNING: Budget exceeded!')
    exit(1)
"
```

## Monthly Budget Planning

**Light Usage** (hobby/testing):
- 10 runs/month × $0.20 = **$2.00/month**

**Medium Usage** (active development):
- 50 runs/month × $0.30 = **$15.00/month**

**Heavy Usage** (research/training):
- 200 runs/month × $0.50 = **$100.00/month**

Compare to:
- AWS EC2 g4dn.xlarge (T4): $0.526/hr = ~$380/month (always on)
- Google Colab Pro: $9.99/month (limited hours)
- Lambda Cloud A100: $1.10/hr = ~$800/month (always on)

**This architecture: $15-100/month** (only pay for what you use)

## Cost Checklist

Before every run:
- [ ] Is spot instance enabled? (if fault-tolerant)
- [ ] Is disk size minimized?
- [ ] Will auto-shutdown catch idle time?
- [ ] Is this the cheapest GPU that meets requirements?
- [ ] Are datasets mounted, not downloaded?
- [ ] Is `--down` flag used for one-off jobs?

## Emergency Stop

If costs get out of control:

```bash
# Stop all clusters immediately
sky down --all --yes

# Or use Vast.ai web UI
# https://cloud.vast.ai/instances/
```