# LLM Training on Vast.ai with Kubernetes

This guide shows how to use the Vast.ai Virtual Kubelet to train LLMs.

## Architecture

```
Your Laptop
    │
    │ kubectl apply -f llm-training-job.yaml
    ▼
k3s Cluster
    │
    │ Schedules to virtual-vastai node
    ▼
vastai-kubelet Pod
    │
    │ Calls Vast.ai API: "Create instance with this image & command"
    ▼
Vast.ai Cloud
    │
    │ Creates GPU container (RTX 4090 / A100)
    ▼
GPU Container (Vast.ai Datacenter)
    │
    ├─ Downloads dataset from HuggingFace
    ├─ Downloads base model from HuggingFace
    ├─ Fine-tunes with LoRA
    ├─ Uploads model to HuggingFace Hub
    └─ (or saves to persistent storage)
```

## The Container Problem

Vast.ai containers are **isolated** - they cannot reach your local MLflow or MinIO.

**Solutions:**

1. **Use HuggingFace Hub** (Recommended for lab)
   - Download datasets/models from HF Hub
   - Upload trained model back to HF Hub
   - No local services needed

2. **Install Tailscale in Container** (Advanced)
   - Container joins your Tailnet
   - Can reach local services via Tailscale IPs

3. **Use Cloud Storage** (Alternative)
   - Upload to AWS S3, GCS, etc.

## Example 1: Fine-tune TinyLlama (Simple)

### Training Script

```python
# train_llm.py
import os
import torch
from datasets import load_dataset
from transformers import (
    AutoModelForCausalLM, AutoTokenizer,
    TrainingArguments, Trainer,
    DataCollatorForLanguageModeling
)
from peft import LoraConfig, get_peft_model, TaskType

# Configuration
MODEL_NAME = os.getenv("MODEL_NAME", "TinyLlama/TinyLlama-1.1B-Chat-v1.0")
DATASET_NAME = os.getenv("DATASET_NAME", "tatsu-lab/alpaca")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/workspace/output")
HF_TOKEN = os.getenv("HF_TOKEN", None)

# Load model & tokenizer
print(f"Loading model: {MODEL_NAME}")
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float16,
    device_map="auto",
    token=HF_TOKEN
)
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, token=HF_TOKEN)
tokenizer.pad_token = tokenizer.eos_token

# Apply LoRA
lora_config = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "v_proj"],
    lora_dropout=0.05,
    bias="none",
    task_type=TaskType.CAUSAL_LM
)
model = get_peft_model(model, lora_config)
print(f"Trainable parameters: {model.print_trainable_parameters()}")

# Load dataset
dataset = load_dataset(DATASET_NAME, split="train[:1000]")

# Tokenize
def tokenize_function(examples):
    return tokenizer(
        examples["text"],
        truncation=True,
        max_length=512,
        padding="max_length"
    )

tokenized_dataset = dataset.map(tokenize_function, batched=True)

# Training arguments
training_args = TrainingArguments(
    output_dir=OUTPUT_DIR,
    num_train_epochs=3,
    per_device_train_batch_size=4,
    gradient_accumulation_steps=4,
    learning_rate=2e-4,
    fp16=True,
    logging_steps=10,
    save_strategy="epoch",
    evaluation_strategy="no",
)

# Train
trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=tokenized_dataset,
    data_collator=DataCollatorForLanguageModeling(tokenizer, mlm=False),
)

print("Starting training...")
trainer.train()

# Save model
print(f"Saving model to {OUTPUT_DIR}")
model.save_pretrained(OUTPUT_DIR)
tokenizer.save_pretrained(OUTPUT_DIR)

# Optionally upload to HuggingFace Hub
if HF_TOKEN and os.getenv("PUSH_TO_HUB", "false").lower() == "true":
    from huggingface_hub import HfApi
    api = HfApi(token=HF_TOKEN)
    repo_id = os.getenv("HF_REPO_ID", "your-username/llm-finetuned")
    api.create_repo(repo_id, exist_ok=True)
    api.upload_folder(folder_path=OUTPUT_DIR, repo_id=repo_id)
    print(f"Model uploaded to https://huggingface.co/{repo_id}")

print("Training complete!")
```

### Kubernetes Job

```yaml
# llm-training-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: llm-training
spec:
  template:
    metadata:
      annotations:
        vast.ai/gpu-name: "RTX 4090"
        vast.ai/max-dph: "0.50"
        vast.ai/disk-gb: "50"
    spec:
      nodeName: virtual-vastai
      restartPolicy: Never
      containers:
      - name: training
        image: huggingface/transformers-pytorch-gpu:latest
        command:
        - /bin/sh
        - -c
        - |
          pip install peft datasets accelerate
          python /workspace/train_llm.py
        env:
        - name: MODEL_NAME
          value: "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
        - name: DATASET_NAME
          value: "tatsu-lab/alpaca"
        - name: OUTPUT_DIR
          value: "/workspace/output"
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-token
              key: token
        - name: PUSH_TO_HUB
          value: "false"
        resources:
          limits:
            nvidia.com/gpu: "1"
        volumeMounts:
        - name: workspace
          mountPath: /workspace
      volumes:
      - name: workspace
        emptyDir:
          sizeLimit: 50Gi
      tolerations:
      - key: "virtual-kubelet.io/provider"
        operator: "Equal"
        value: "vastai"
        effect: "NoSchedule"
```

### Run Training

```bash
# 1. Create HF token secret (optional, for pushing models)
kubectl create secret generic hf-token \
  --from-literal=token=hf_xxxxxxxxxxxxx \
  -n default

# 2. Submit training job
kubectl apply -f llm-training-job.yaml

# 3. Watch instance creation
kubectl logs -n vastai-system deployment/vastai-kubelet -f

# 4. Monitor training
kubectl logs -f job/llm-training

# 5. Check status
kubectl get job llm-training
kubectl get pods -o wide | grep llm-training
```

## Example 2: Using a Custom Training Image

### Dockerfile

```dockerfile
FROM nvidia/cuda:12.1-devel-ubuntu22.04

# Install Python & dependencies
RUN apt-get update && apt-get install -y python3-pip git && \
    rm -rf /var/lib/apt/lists/*

# Install ML packages
RUN pip3 install --no-cache-dir \
    torch torchvision torchaudio \
    transformers datasets accelerate \
    peft bitsandbytes scipy

# Copy training script
COPY train_llm.py /workspace/train_llm.py
WORKDIR /workspace

# Default command
CMD ["python3", "train_llm.py"]
```

### Build & Push

```bash
# Build image
docker build -t localhost:5000/llm-trainer:latest .

# Push to local registry
docker push localhost:5000/llm-trainer:latest

# Update job to use custom image
# image: localhost:5000/llm-trainer:latest
```

## Example 3: Multi-GPU Training

```yaml
# multi-gpu-training.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: multi-gpu-llm-training
spec:
  template:
    metadata:
      annotations:
        vast.ai/gpu-name: "RTX 4090"
        vast.ai/max-dph: "1.00"
        vast.ai/disk-gb: "100"
    spec:
      nodeName: virtual-vastai
      restartPolicy: Never
      containers:
      - name: training
        image: huggingface/transformers-pytorch-gpu:latest
        command:
        - torchrun
        - --nproc_per_node=2
        - /workspace/train_distributed.py
        env:
        - name: MODEL_NAME
          value: "meta-llama/Llama-2-7b-hf"
        - name: GPUS
          value: "2"
        resources:
          limits:
            nvidia.com/gpu: "2"  # Request 2 GPUs
```

## Getting Your Model Back

### Option 1: HuggingFace Hub (Easiest)

```python
# In training script
from huggingface_hub import HfApi

api = HfApi(token=os.getenv("HF_TOKEN"))
api.upload_folder(
    folder_path="/workspace/output",
    repo_id="your-username/my-finetuned-model"
)
```

### Option 2: SCP from Vast.ai Instance

```bash
# Get instance SSH info from Vast.ai web UI
# SSH into instance and download model
scp -P <port> root@ssh.vast.ai:/workspace/output ./my-model/
```

### Option 3: Install Tailscale in Container

```yaml
# Add to your job init command:
command:
- /bin/sh
- -c
- |
  # Install Tailscale
  curl -fsSL https://tailscale.com/install.sh | sh
  tailscaled --tun=userspace-networking --socks5-server=localhost:1080 &
  tailscale up --authkey=$TS_AUTHKEY
  
  # Set proxy for uploads
  export HTTP_PROXY=socks5://localhost:1080
  export HTTPS_PROXY=socks5://localhost:1080
  
  # Now you can reach your local MinIO/MLflow
  python train_llm.py
env:
- name: TS_AUTHKEY
  valueFrom:
    secretKeyRef:
      name: tailscale-auth
      key: key
```

## Example 4: Full Pipeline with MLflow Tracking

```python
# train_with_mlflow.py
import os
import mlflow
import mlflow.pytorch

# Connect to MLflow (requires MLflow to be accessible)
# Option 1: Public MLflow
mlflow.set_tracking_uri(os.getenv("MLFLOW_URI", "http://your-mlflow-server:5000"))

# Option 2: MLflow via Tailscale proxy
# export HTTP_PROXY=socks5://localhost:1080
# mlflow.set_tracking_uri("http://100.87.186.22:30500")

mlflow.set_experiment("llm-finetuning")

with mlflow.start_run():
    # Log parameters
    mlflow.log_param("model", MODEL_NAME)
    mlflow.log_param("epochs", 3)
    mlflow.log_param("lr", 2e-4)
    
    # Train...
    trainer.train()
    
    # Log metrics
    mlflow.log_metric("final_loss", trainer.state.log_history[-1]["loss"])
    
    # Log model
    mlflow.pytorch.log_model(model, "model")
```

## Cost Estimation

| Model | GPU | Time | Cost (at $0.50/hr) |
|-------|-----|------|-------------------|
| TinyLlama (1.1B) | RTX 4090 | 30 min | $0.25 |
| Llama-2-7B | A100 | 2 hours | $1.00 |
| Llama-2-13B | A100 | 4 hours | $2.00 |
| Mistral-7B | RTX 4090 | 3 hours | $1.50 |

## Monitoring Training

```bash
# Watch instance creation
kubectl get events --field-selector involvedObject.name=llm-training

# Check pod logs
kubectl logs -f job/llm-training

# Check Vast.ai controller logs
kubectl logs -n vastai-system deployment/vastai-kubelet -f

# Check Vast.ai instance status
curl -s -H "Authorization: Bearer $VASTAI_KEY" \
  https://console.vast.ai/api/v0/instances/ | \
  jq '.instances[] | {id, status, gpu_name, dph_total}'
```

## Tips for Lab Use

1. **Start small**: Use TinyLlama first to test the pipeline
2. **Use LoRA**: Much faster and cheaper than full fine-tuning
3. **Set disk size**: Models + checkpoints need space (20-100GB)
4. **Save checkpoints**: In case instance is preempted
5. **Use spot instances**: Cheaper but can be interrupted
6. **Test locally first**: Run training script on CPU to verify it works

## Troubleshooting

### Container can't download model

```bash
# Check internet connectivity in container
kubectl exec -it job/llm-training -- curl -I https://huggingface.co

# If blocked, Vast.ai instance may need proxy configuration
```

### Out of GPU memory

```python
# Use quantization
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    load_in_8bit=True,  # or load_in_4bit=True
    device_map="auto"
)
```

### Training too slow

- Use smaller model (TinyLlama vs Llama-2-7B)
- Increase batch size if GPU memory allows
- Use gradient accumulation
- Use mixed precision (fp16)

## Next Steps

1. Try Example 1 with TinyLlama
2. Push model to HuggingFace Hub
3. Create inference endpoint with the fine-tuned model
4. Build a Kubeflow pipeline that automates this workflow