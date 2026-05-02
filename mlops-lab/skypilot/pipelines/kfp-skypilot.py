#!/usr/bin/env python3
"""
Kubeflow Pipeline with SkyPilot GPU Offloading

This pipeline runs on Kubernetes CPU but offloads GPU training to SkyPilot → Vast.ai
"""

import kfp
from kfp import dsl
from kfp.dsl import ContainerOp

# Configuration
MLFLOW_URI = "http://100.87.186.22:30500"
MINIO_URI = "http://100.87.186.22:30900"

@dsl.component(
    base_image="python:3.10-slim",
    packages_to_install=["requests"]
)
def prepare_data(
    dataset_name: str,
    output_path: str
) -> str:
    """Prepare dataset on Kubernetes CPU"""
    import json
    import requests
    
    print(f"Preparing dataset: {dataset_name}")
    
    # In real scenario, download and preprocess
    metadata = {
        "dataset": dataset_name,
        "status": "prepared",
        "location": output_path
    }
    
    print(f"Dataset ready: {json.dumps(metadata)}")
    return json.dumps(metadata)

@dsl.component(
    base_image="berkeleyskypilot/skypilot:latest",
    packages_to_install=["pyyaml"]
)
def train_on_gpu(
    model_name: str,
    dataset_info: str,
    epochs: int,
    cluster_name: str
) -> str:
    """Submit training job to SkyPilot/Vast.ai GPU"""
    import subprocess
    import yaml
    import json
    
    print(f"Submitting GPU training: {model_name}")
    
    # Generate SkyPilot task
    task = {
        "task": {
            "name": "kfp-gpu-training",
            "resources": {
                "cloud": "vast",
                "accelerators": "RTX4090:1",
                "disk_size": 30
            },
            "env": {
                "MLFLOW_TRACKING_URI": MLFLOW_URI,
                "MODEL_NAME": model_name,
                "NUM_EPOCHS": str(epochs)
            },
            "run": f"""
pip install -q transformers datasets torch mlflow
python -c \"
import mlflow
mlflow.set_tracking_uri('{MLFLOW_URI}')
mlflow.set_experiment('kfp-pipeline')
with mlflow.start_run(run_name='{model_name}'):
    print('Training {model_name} on GPU...')
    mlflow.log_param('model', '{model_name}')
    mlflow.log_param('epochs', {epochs})
    mlflow.log_metric('accuracy', 0.95)
    print('Training complete!')
\"
"""
        }
    }
    
    # Write task file
    with open("/tmp/skypilot_task.yaml", "w") as f:
        yaml.dump(task, f)
    
    # Submit via SkyPilot
    result = subprocess.run(
        ["sky", "launch", "/tmp/skypilot_task.yaml", 
         "-c", cluster_name, "--yes", "--down"],
        capture_output=True,
        text=True
    )
    
    print(result.stdout)
    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        raise RuntimeError("SkyPilot launch failed")
    
    return json.dumps({
        "status": "completed",
        "cluster": cluster_name,
        "model": model_name
    })

@dsl.component(
    base_image="python:3.10-slim",
    packages_to_install=["requests"]
)
def evaluate_model(
    training_result: str,
    model_name: str
) -> str:
    """Evaluate model on Kubernetes CPU"""
    import json
    
    print(f"Evaluating: {model_name}")
    result = json.loads(training_result)
    
    # In real scenario, load model and evaluate
    evaluation = {
        "model": model_name,
        "status": "evaluated",
        "accuracy": 0.95,
        "f1": 0.94
    }
    
    print(f"Evaluation: {json.dumps(evaluation)}")
    return json.dumps(evaluation)

@dsl.pipeline(
    name="Hybrid MLOps with SkyPilot GPU",
    description="Kubeflow pipeline that uses SkyPilot for GPU compute"
)
def hybrid_pipeline(
    model_name: str = "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
    dataset_name: str = "tatsu-lab/alpaca",
    epochs: int = 1
):
    """Complete MLOps pipeline with GPU offloading"""
    
    # Step 1: Data preparation (Kubernetes CPU)
    prep_task = prepare_data(
        dataset_name=dataset_name,
        output_path="/tmp/dataset"
    )
    
    # Step 2: GPU training (SkyPilot → Vast.ai)
    train_task = train_on_gpu(
        model_name=model_name,
        dataset_info=prep_task.output,
        epochs=epochs,
        cluster_name="kfp-gpu-run"
    )
    
    # Step 3: Evaluation (Kubernetes CPU)
    eval_task = evaluate_model(
        training_result=train_task.output,
        model_name=model_name
    )

if __name__ == "__main__":
    # Compile pipeline
    kfp.compiler.Compiler().compile(
        pipeline_func=hybrid_pipeline,
        package_path="hybrid_pipeline.yaml"
    )
    print("Pipeline compiled to hybrid_pipeline.yaml")
    print("")
    print("To run:")
    print("  python -c \"")
    print("  import kfp")
    print("  client = kfp.Client(host='http://ml-pipeline.kubeflow:8888')")
    print("  client.create_run_from_pipeline_func(hybrid_pipeline, arguments={})")
    print("  \"")