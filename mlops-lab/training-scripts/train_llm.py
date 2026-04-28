import os
import torch
from datasets import load_dataset
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    TrainingArguments,
    Trainer,
    DataCollatorForLanguageModeling
)
from peft import LoraConfig, get_peft_model, TaskType

# Configuration from environment
MODEL_NAME = os.getenv("MODEL_NAME", "TinyLlama/TinyLlama-1.1B-Chat-v1.0")
DATASET_NAME = os.getenv("DATASET_NAME", "tatsu-lab/alpaca")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/workspace/output")
HF_TOKEN = os.getenv("HF_TOKEN", None)
NUM_EPOCHS = int(os.getenv("NUM_EPOCHS", "3"))
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "4"))
LEARNING_RATE = float(os.getenv("LEARNING_RATE", "2e-4"))
MAX_LENGTH = int(os.getenv("MAX_LENGTH", "512"))
LORA_R = int(os.getenv("LORA_R", "16"))
LORA_ALPHA = int(os.getenv("LORA_ALPHA", "32"))

print(f"=== LLM Training Configuration ===")
print(f"Model: {MODEL_NAME}")
print(f"Dataset: {DATASET_NAME}")
print(f"Epochs: {NUM_EPOCHS}")
print(f"Batch Size: {BATCH_SIZE}")
print(f"Learning Rate: {LEARNING_RATE}")
print(f"Output: {OUTPUT_DIR}")
print()

# Create output directory
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Check GPU
if torch.cuda.is_available():
    print(f"GPU: {torch.cuda.get_device_name(0)}")
    print(f"GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
else:
    print("WARNING: No GPU detected!")
    print("Training will be very slow on CPU.")

print()

# Load model & tokenizer
print(f"Loading model: {MODEL_NAME}")
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float16,
    device_map="auto",
    token=HF_TOKEN
)
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, token=HF_TOKEN)
if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token

# Apply LoRA for efficient fine-tuning
print("Applying LoRA...")
lora_config = LoraConfig(
    r=LORA_R,
    lora_alpha=LORA_ALPHA,
    target_modules=["q_proj", "v_proj", "k_proj", "o_proj"],
    lora_dropout=0.05,
    bias="none",
    task_type=TaskType.CAUSAL_LM
)
model = get_peft_model(model, lora_config)

# Print trainable parameters
trainable_params = sum(p.numel() for p in model.parameters() if p.requires_grad)
all_params = sum(p.numel() for p in model.parameters())
print(f"Trainable parameters: {trainable_params:,} / {all_params:,} ({100 * trainable_params / all_params:.2f}%)")
print()

# Load dataset
print(f"Loading dataset: {DATASET_NAME}")
dataset = load_dataset(DATASET_NAME, split="train[:1000]")
print(f"Dataset size: {len(dataset)}")
print(f"Features: {list(dataset.features.keys())}")
print()

# Tokenize dataset
def format_alpaca(example):
    """Format Alpaca dataset for causal LM"""
    if 'instruction' in example and 'output' in example:
        text = f"### Instruction:\n{example['instruction']}\n\n### Response:\n{example['output']}"
    elif 'text' in example:
        text = example['text']
    else:
        text = str(example)
    return {'text': text}

def tokenize_function(examples):
    return tokenizer(
        examples["text"],
        truncation=True,
        max_length=MAX_LENGTH,
        padding="max_length"
    )

print("Formatting dataset...")
if 'instruction' in dataset.features:
    dataset = dataset.map(format_alpaca)

tokenized_dataset = dataset.map(
    tokenize_function,
    batched=True,
    remove_columns=dataset.column_names
)

print(f"Tokenized dataset size: {len(tokenized_dataset)}")
print()

# Training arguments
training_args = TrainingArguments(
    output_dir=OUTPUT_DIR,
    num_train_epochs=NUM_EPOCHS,
    per_device_train_batch_size=BATCH_SIZE,
    gradient_accumulation_steps=4,
    learning_rate=LEARNING_RATE,
    fp16=True,
    logging_steps=10,
    save_strategy="epoch",
    save_total_limit=2,
    evaluation_strategy="no",
    report_to="none",  # Change to "tensorboard" or "mlflow" if configured
    load_best_model_at_end=False,
)

# Data collator
data_collator = DataCollatorForLanguageModeling(
    tokenizer=tokenizer,
    mlm=False  # We're doing causal LM, not masked LM
)

# Initialize trainer
trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=tokenized_dataset,
    data_collator=data_collator,
)

# Train
print("=" * 50)
print("Starting training...")
print("=" * 50)
print()

trainer.train()

print()
print("=" * 50)
print("Training complete!")
print("=" * 50)
print()

# Save model
print(f"Saving model to {OUTPUT_DIR}")
model.save_pretrained(os.path.join(OUTPUT_DIR, "final_model"))
tokenizer.save_pretrained(os.path.join(OUTPUT_DIR, "final_model"))

# Save training info
with open(os.path.join(OUTPUT_DIR, "training_info.txt"), "w") as f:
    f.write(f"Model: {MODEL_NAME}\n")
    f.write(f"Dataset: {DATASET_NAME}\n")
    f.write(f"Epochs: {NUM_EPOCHS}\n")
    f.write(f"Batch Size: {BATCH_SIZE}\n")
    f.write(f"Learning Rate: {LEARNING_RATE}\n")
    f.write(f"LoRA Rank: {LORA_R}\n")
    f.write(f"LoRA Alpha: {LORA_ALPHA}\n")
    f.write(f"Trainable Params: {trainable_params:,}\n")

print(f"Model saved to {OUTPUT_DIR}/final_model")
print(f"Training info saved to {OUTPUT_DIR}/training_info.txt")

# Optionally push to HuggingFace Hub
if HF_TOKEN and os.getenv("PUSH_TO_HUB", "false").lower() == "true":
    print()
    print("Pushing to HuggingFace Hub...")
    from huggingface_hub import HfApi
    
    api = HfApi(token=HF_TOKEN)
    repo_id = os.getenv("HF_REPO_ID", "your-username/llm-finetuned")
    
    try:
        api.create_repo(repo_id, exist_ok=True)
        api.upload_folder(
            folder_path=os.path.join(OUTPUT_DIR, "final_model"),
            repo_id=repo_id
        )
        print(f"Model uploaded to https://huggingface.co/{repo_id}")
    except Exception as e:
        print(f"Error uploading to Hub: {e}")

print()
print("Done!")
print(f"You can download the model from the Vast.ai instance or use 'scp' to copy it locally.")