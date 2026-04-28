import kfp
from kfp import dsl
from kfp.dsl import (
    Input, Output, Dataset, Model, Metrics,
    ContainerOp, pipeline
)

# Pipeline configuration
MLFLOW_TRACKING_URI = "http://mlflow.mlops:5000"
MINIO_ENDPOINT = "http://minio.mlops:9000"
HF_MODEL_NAME = "distilbert-base-uncased"
DATASET_NAME = "imdb"

@dsl.component(
    base_image="python:3.10-slim",
    packages_to_install=[
        "datasets", "transformers", "torch", 
        "mlflow", "boto3", "scikit-learn"
    ]
)
def download_dataset(
    dataset_name: str,
    output_path: Output[Dataset]
):
    """Download and prepare dataset from HuggingFace"""
    from datasets import load_dataset
    import json
    
    dataset = load_dataset(dataset_name, split="train[:1000]")
    dataset.save_to_disk(output_path.path)
    
    # Save metadata
    with open(f"{output_path.path}/metadata.json", "w") as f:
        json.dump({
            "dataset": dataset_name,
            "size": len(dataset),
            "features": list(dataset.features.keys())
        }, f)

@dsl.component(
    base_image="python:3.10-slim",
    packages_to_install=[
        "datasets", "transformers", "torch", 
        "mlflow", "accelerate", "scikit-learn"
    ]
)
def train_model(
    model_name: str,
    dataset_path: Input[Dataset],
    model_output: Output[Model],
    metrics_output: Output[Metrics],
    epochs: int = 3,
    batch_size: int = 8,
    learning_rate: float = 2e-5
):
    """Fine-tune DistilBERT on IMDB dataset"""
    import os
    import json
    import mlflow
    import torch
    from datasets import load_from_disk
    from transformers import (
        AutoTokenizer, AutoModelForSequenceClassification,
        TrainingArguments, Trainer
    )
    from sklearn.metrics import accuracy_score, precision_recall_fscore_support
    
    # Setup MLflow
    os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://minio.mlops:9000"
    os.environ["AWS_ACCESS_KEY_ID"] = "minioadmin"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "minioadmin123"
    mlflow.set_tracking_uri("http://mlflow.mlops:5000")
    mlflow.set_experiment("huggingface-text-classification")
    
    with mlflow.start_run():
        # Log parameters
        mlflow.log_params({
            "model": model_name,
            "epochs": epochs,
            "batch_size": batch_size,
            "learning_rate": learning_rate
        })
        
        # Load dataset
        dataset = load_from_disk(dataset_path.path)
        
        # Initialize tokenizer and model
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForSequenceClassification.from_pretrained(
            model_name, 
            num_labels=2
        )
        
        # Tokenize dataset
        def tokenize_function(examples):
            return tokenizer(
                examples["text"], 
                padding="max_length", 
                truncation=True, 
                max_length=512
            )
        
        tokenized_dataset = dataset.map(tokenize_function, batched=True)
        tokenized_dataset = tokenized_dataset.rename_column("label", "labels")
        tokenized_dataset.set_format("torch")
        
        # Split dataset
        train_size = int(0.8 * len(tokenized_dataset))
        train_dataset = tokenized_dataset.select(range(train_size))
        eval_dataset = tokenized_dataset.select(range(train_size, len(tokenized_dataset)))
        
        # Training arguments
        training_args = TrainingArguments(
            output_dir="/tmp/results",
            num_train_epochs=epochs,
            per_device_train_batch_size=batch_size,
            per_device_eval_batch_size=batch_size,
            learning_rate=learning_rate,
            weight_decay=0.01,
            evaluation_strategy="epoch",
            save_strategy="epoch",
            load_best_model_at_end=True,
        )
        
        # Define compute metrics
        def compute_metrics(pred):
            labels = pred.label_ids
            preds = pred.predictions.argmax(-1)
            precision, recall, f1, _ = precision_recall_fscore_support(
                labels, preds, average="binary"
            )
            acc = accuracy_score(labels, preds)
            return {
                "accuracy": acc,
                "f1": f1,
                "precision": precision,
                "recall": recall
            }
        
        # Train
        trainer = Trainer(
            model=model,
            args=training_args,
            train_dataset=train_dataset,
            eval_dataset=eval_dataset,
            compute_metrics=compute_metrics,
        )
        
        trainer.train()
        
        # Evaluate
        eval_results = trainer.evaluate()
        
        # Log metrics
        mlflow.log_metrics(eval_results)
        
        # Save model
        model.save_pretrained(model_output.path)
        tokenizer.save_pretrained(model_output.path)
        
        # Save metrics
        with open(metrics_output.path, "w") as f:
            json.dump(eval_results, f)
        
        # Log model to MLflow
        mlflow.pytorch.log_model(model, "model")
        
        print(f"Training complete! Results: {eval_results}")

@dsl.component(
    base_image="python:3.10-slim",
    packages_to_install=["transformers", "torch", "requests"]
)
def deploy_model(
    model_path: Input[Model],
    model_name: str
):
    """Deploy model to KServe (placeholder - would create InferenceService)"""
    import json
    
    # In real scenario, this would create a KServe InferenceService
    deployment_config = {
        "apiVersion": "serving.kserve.io/v1beta1",
        "kind": "InferenceService",
        "metadata": {
            "name": f"{model_name.replace('/', '-')}"
        },
        "spec": {
            "predictor": {
                "model": {
                    "modelFormat": {"name": "huggingface"},
                    "storageUri": f"s3://models/{model_name}"
                }
            }
        }
    }
    
    print(f"Deployment config: {json.dumps(deployment_config, indent=2)}")
    print("Note: Apply this manifest manually or via CI/CD")

@dsl.pipeline(
    name="HuggingFace Text Classification",
    description="Fine-tune DistilBERT on IMDB reviews"
)
def hf_pipeline(
    model_name: str = HF_MODEL_NAME,
    dataset_name: str = DATASET_NAME,
    epochs: int = 3,
    batch_size: int = 8,
    learning_rate: float = 2e-5
):
    """Complete MLOps pipeline for text classification"""
    
    # Step 1: Download dataset
    download_task = download_dataset(dataset_name=dataset_name)
    
    # Step 2: Train model
    train_task = train_model(
        model_name=model_name,
        dataset_path=download_task.outputs["output_path"],
        epochs=epochs,
        batch_size=batch_size,
        learning_rate=learning_rate
    )
    
    # Step 3: Deploy model
    deploy_task = deploy_model(
        model_path=train_task.outputs["model_output"],
        model_name=model_name
    )

if __name__ == "__main__":
    # Compile pipeline
    kfp.compiler.Compiler().compile(
        pipeline_func=hf_pipeline,
        package_path="hf_text_classification.yaml"
    )
    print("Pipeline compiled to hf_text_classification.yaml")