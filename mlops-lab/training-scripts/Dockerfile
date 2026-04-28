FROM nvidia/cuda:12.1-devel-ubuntu22.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3-pip \
    python3-dev \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip3 install --upgrade pip

# Install ML packages
RUN pip3 install --no-cache-dir \
    torch==2.1.0 \
    torchvision \
    torchaudio \
    transformers==4.36.0 \
    datasets \
    accelerate \
    peft \
    bitsandbytes \
    scipy \
    huggingface-hub

# Create workspace
WORKDIR /workspace

# Copy training script
COPY train_llm.py /workspace/train_llm.py

# Default command
CMD ["python3", "/workspace/train_llm.py"]