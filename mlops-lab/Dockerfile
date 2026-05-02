FROM pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime

LABEL maintainer="MLOps Lab"
LABEL description="GPU Training Container for LLM Fine-tuning"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3-pip \
    python3-dev \
    git \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install --no-cache-dir \
    torch==2.3.0 \
    transformers==4.45.0 \
    datasets \
    accelerate \
    peft \
    bitsandbytes \
    mlflow \
    boto3 \
    scipy \
    huggingface-hub

# Create workspace
WORKDIR /workspace

# Copy training scripts
COPY training-scripts/ /workspace/

# Set environment defaults
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/workspace/huggingface_cache

# Default command
CMD ["python3", "/workspace/train_llm.py"]
