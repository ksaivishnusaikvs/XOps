#!/usr/bin/env python3
"""
MLOps Pipeline Configuration with MLflow and Kubeflow

This module provides complete ML pipeline implementations including:
- Training pipeline with Kubeflow
- Model serving with KServe
- LLM deployment and serving
- Model monitoring and drift detection
- Vector database for RAG
- A/B testing capabilities
- AutoML pipeline

Directory Structure:
mlops-project/
├── data/
│   ├── raw/
│   ├── processed/
│   └── features/
├── models/
│   ├── training/
│   └── serving/
├── pipelines/
│   ├── training_pipeline.py
│   ├── inference_pipeline.py
│   └── monitoring_pipeline.py
├── src/
│   ├── data_processing.py
│   ├── feature_engineering.py
│   ├── model_training.py
│   └── model_serving.py
├── tests/
├── configs/
│   ├── model_config.yaml
│   └── pipeline_config.yaml
└── mlops_setup.sh

Usage:
    python mlops-pipeline.py
"""

# ============================================================================
# PART 1: ML Training Pipeline (Kubeflow)
# ============================================================================
# pipelines/training_pipeline.py
import kfp
from kfp import dsl
from kfp.components import create_component_from_func

@create_component_from_func
def load_data(data_path: str) -> str:
    """Load and validate training data"""
    import pandas as pd
    import json
    
    df = pd.read_csv(data_path)
    
    # Data validation
    assert not df.isnull().any().any(), "Data contains null values"
    assert len(df) > 1000, "Insufficient data"
    
    # Save processed data
    output_path = "/tmp/processed_data.csv"
    df.to_csv(output_path, index=False)
    
    return output_path

@create_component_from_func
def feature_engineering(data_path: str) -> str:
    """Engineer features from raw data"""
    import pandas as pd
    from sklearn.preprocessing import StandardScaler
    import joblib
    
    df = pd.read_csv(data_path)
    
    # Feature engineering logic
    scaler = StandardScaler()
    features = scaler.fit_transform(df.drop('target', axis=1))
    
    # Save scaler
    joblib.dump(scaler, '/tmp/scaler.pkl')
    
    # Save features
    feature_path = "/tmp/features.csv"
    pd.DataFrame(features).to_csv(feature_path, index=False)
    
    return feature_path

@create_component_from_func
def train_model(
    feature_path: str,
    model_type: str = 'random_forest',
    n_estimators: int = 100
) -> str:
    """Train ML model"""
    import pandas as pd
    import mlflow
    import mlflow.sklearn
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import accuracy_score, f1_score, roc_auc_score
    import joblib
    
    # Load features
    df = pd.read_csv(feature_path)
    X = df.drop('target', axis=1) if 'target' in df.columns else df
    y = df['target'] if 'target' in df.columns else None
    
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    
    # Start MLflow run
    with mlflow.start_run():
        # Train model
        model = RandomForestClassifier(n_estimators=n_estimators, random_state=42)
        model.fit(X_train, y_train)
        
        # Evaluate
        y_pred = model.predict(X_test)
        y_proba = model.predict_proba(X_test)[:, 1]
        
        accuracy = accuracy_score(y_test, y_pred)
        f1 = f1_score(y_test, y_pred, average='weighted')
        auc = roc_auc_score(y_test, y_proba)
        
        # Log metrics
        mlflow.log_param("model_type", model_type)
        mlflow.log_param("n_estimators", n_estimators)
        mlflow.log_metric("accuracy", accuracy)
        mlflow.log_metric("f1_score", f1)
        mlflow.log_metric("roc_auc", auc)
        
        # Log model
        mlflow.sklearn.log_model(model, "model")
        
        # Save model locally
        model_path = "/tmp/model.pkl"
        joblib.dump(model, model_path)
        
        print(f"Model trained - Accuracy: {accuracy:.4f}, F1: {f1:.4f}, AUC: {auc:.4f}")
        
        return model_path

@dsl.pipeline(
    name='ML Training Pipeline',
    description='End-to-end ML training pipeline with MLflow tracking'
)
def ml_training_pipeline(
    data_path: str = 's3://data/train.csv',
    model_type: str = 'random_forest',
    n_estimators: int = 100
):
    """Complete ML training pipeline"""
    # Step 1: Load data
    load_data_task = load_data(data_path=data_path)
    
    # Step 2: Feature engineering
    feature_task = feature_engineering(data_path=load_data_task.output)
    
    # Step 3: Train model
    train_task = train_model(
        feature_path=feature_task.output,
        model_type=model_type,
        n_estimators=n_estimators
    )

# Compile pipeline
if __name__ == '__main__':
    kfp.compiler.Compiler().compile(
        ml_training_pipeline,
        'ml_training_pipeline.yaml'
    )


# ============================================================================
# PART 2: LLM Deployment and Serving
# ============================================================================
# src/llm_serving.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from prometheus_client import Counter, Histogram, generate_latest
import time

app = FastAPI(title="LLM Serving API")

# Prometheus metrics
REQUEST_COUNT = Counter('llm_requests_total', 'Total LLM requests')
REQUEST_DURATION = Histogram('llm_request_duration_seconds', 'LLM request duration')
TOKENS_GENERATED = Counter('llm_tokens_generated_total', 'Total tokens generated')

class GenerateRequest(BaseModel):
    prompt: str
    max_tokens: int = 100
    temperature: float = 0.7
    top_p: float = 0.9

class GenerateResponse(BaseModel):
    text: str
    tokens_used: int
    model: str

# Load model at startup
MODEL_NAME = "gpt2"  # Replace with your model
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModelForCausalLM.from_pretrained(MODEL_NAME)

if torch.cuda.is_available():
    model = model.cuda()

@app.post("/generate", response_model=GenerateResponse)
async def generate(request: GenerateRequest):
    """Generate text from LLM"""
    REQUEST_COUNT.inc()
    start_time = time.time()
    
    try:
        # Tokenize input
        inputs = tokenizer(request.prompt, return_tensors="pt")
        if torch.cuda.is_available():
            inputs = inputs.to("cuda")
        
        # Generate
        with torch.no_grad():
            outputs = model.generate(
                inputs["input_ids"],
                max_new_tokens=request.max_tokens,
                temperature=request.temperature,
                top_p=request.top_p,
                do_sample=True
            )
        
        # Decode
        generated_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
        tokens_used = len(outputs[0])
        
        # Update metrics
        TOKENS_GENERATED.inc(tokens_used)
        REQUEST_DURATION.observe(time.time() - start_time)
        
        return GenerateResponse(
            text=generated_text,
            tokens_used=tokens_used,
            model=MODEL_NAME
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    return {"status": "healthy", "model": MODEL_NAME}

@app.get("/metrics")
async def metrics():
    return generate_latest()


# ============================================================================
# PART 3: Model Monitoring and Drift Detection
# ============================================================================
# pipelines/monitoring_pipeline.py
import pandas as pd
import numpy as np
from evidently.report import Report
from evidently.metric_preset import DataDriftPreset, TargetDriftPreset
from evidently.metrics import *
import mlflow

def detect_data_drift(reference_data: pd.DataFrame, current_data: pd.DataFrame) -> dict:
    """Detect data drift using Evidently"""
    
    # Create drift report
    report = Report(metrics=[
        DataDriftPreset(),
        TargetDriftPreset(),
    ])
    
    report.run(reference_data=reference_data, current_data=current_data)
    
    # Extract metrics
    drift_metrics = report.as_dict()
    
    # Log to MLflow
    with mlflow.start_run(run_name="drift_detection"):
        mlflow.log_dict(drift_metrics, "drift_report.json")
        
        # Check if drift detected
        drift_detected = drift_metrics['metrics'][0]['result']['dataset_drift']
        mlflow.log_metric("drift_detected", int(drift_detected))
        
        if drift_detected:
            print("⚠️ Data drift detected!")
            send_alert("Data drift detected in production model", "WARNING")
        else:
            print("✅ No significant drift detected")
    
    return drift_metrics

def monitor_model_performance(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    threshold_accuracy: float = 0.85
):
    """Monitor model performance metrics"""
    from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
    
    accuracy = accuracy_score(y_true, y_pred)
    precision = precision_score(y_true, y_pred, average='weighted')
    recall = recall_score(y_true, y_pred, average='weighted')
    f1 = f1_score(y_true, y_pred, average='weighted')
    
    # Log to MLflow
    with mlflow.start_run(run_name="model_monitoring"):
        mlflow.log_metric("accuracy", accuracy)
        mlflow.log_metric("precision", precision)
        mlflow.log_metric("recall", recall)
        mlflow.log_metric("f1_score", f1)
        
        # Alert if performance degrades
        if accuracy < threshold_accuracy:
            send_alert(
                f"Model accuracy ({accuracy:.2f}) below threshold ({threshold_accuracy})",
                "CRITICAL"
            )

def send_alert(message: str, severity: str = "INFO"):
    """Send alert to monitoring system"""
    import requests
    
    # Send to Slack/PagerDuty/etc
    webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    payload = {
        "text": f"[{severity}] {message}"
    }
    requests.post(webhook_url, json=payload)


# ============================================================================
# PART 4: Vector Database for RAG (Retrieval-Augmented Generation)
# ============================================================================
# src/vector_store.py
from langchain.embeddings import OpenAIEmbeddings
from langchain.vectorstores import Pinecone
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.document_loaders import DirectoryLoader
import pinecone

# Initialize Pinecone
pinecone.init(
    api_key="your-api-key",
    environment="us-east-1-aws"
)

index_name = "llm-knowledge-base"

def setup_vector_store(docs_directory: str):
    """Setup vector store from documents"""
    
    # Load documents
    loader = DirectoryLoader(docs_directory, glob="**/*.txt")
    documents = loader.load()
    
    # Split into chunks
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200
    )
    texts = text_splitter.split_documents(documents)
    
    # Create embeddings
    embeddings = OpenAIEmbeddings()
    
    # Create vector store
    vectorstore = Pinecone.from_documents(
        texts,
        embeddings,
        index_name=index_name
    )
    
    return vectorstore

def query_knowledge_base(query: str, k: int = 5):
    """Query vector store for relevant documents"""
    
    embeddings = OpenAIEmbeddings()
    vectorstore = Pinecone.from_existing_index(index_name, embeddings)
    
    # Similarity search
    docs = vectorstore.similarity_search(query, k=k)
    
    return docs


# ============================================================================
# PART 5: AutoML Pipeline with Hyperparameter Tuning
# ============================================================================
# pipelines/automl_pipeline.py
from sklearn.model_selection import GridSearchCV
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.svm import SVC
import mlflow
import mlflow.sklearn

def automl_pipeline(X_train, y_train, X_test, y_test):
    """Automated ML pipeline with hyperparameter tuning"""
    
    models = {
        'random_forest': {
            'model': RandomForestClassifier(random_state=42),
            'params': {
                'n_estimators': [50, 100, 200],
                'max_depth': [10, 20, None],
                'min_samples_split': [2, 5, 10]
            }
        },
        'gradient_boosting': {
            'model': GradientBoostingClassifier(random_state=42),
            'params': {
                'n_estimators': [50, 100, 200],
                'learning_rate': [0.01, 0.1, 0.2],
                'max_depth': [3, 5, 7]
            }
        },
        'logistic_regression': {
            'model': LogisticRegression(random_state=42, max_iter=1000),
            'params': {
                'C': [0.1, 1, 10],
                'penalty': ['l1', 'l2'],
                'solver': ['liblinear']
            }
        }
    }
    
    best_models = {}
    
    # Try each model with grid search
    for model_name, config in models.items():
        print(f"\n🔍 Training {model_name}...")
        
        with mlflow.start_run(run_name=f"automl_{model_name}"):
            # Grid search
            grid_search = GridSearchCV(
                config['model'],
                config['params'],
                cv=5,
                scoring='accuracy',
                n_jobs=-1,
                verbose=1
            )
            
            grid_search.fit(X_train, y_train)
            
            # Best model
            best_model = grid_search.best_estimator_
            best_score = grid_search.best_score_
            
            # Test performance
            test_score = best_model.score(X_test, y_test)
            
            # Log to MLflow
            mlflow.log_params(grid_search.best_params_)
            mlflow.log_metric("cv_score", best_score)
            mlflow.log_metric("test_score", test_score)
            mlflow.sklearn.log_model(best_model, f"{model_name}_model")
            
            best_models[model_name] = {
                'model': best_model,
                'params': grid_search.best_params_,
                'score': test_score
            }
            
            print(f"✅ {model_name} - CV Score: {best_score:.4f}, Test Score: {test_score:.4f}")
        
        # Select best overall model
        best_model_name = max(best_models, key=lambda x: best_models[x]['score'])
        print(f"\nBest model: {best_model_name}")
        print(f"Best score: {best_models[best_model_name]['score']:.4f}")
        
        return best_models[best_model_name]


# ============================================================================
# Main Execution
# ============================================================================

if __name__ == "__main__":
    print("MLOps Pipeline Module Loaded Successfully")
    print("Available components:")
    print("  - Kubeflow Training Pipeline")
    print("  - LLM Serving with FastAPI")
    print("  - Model Monitoring with Evidently")
    print("  - Vector Store for RAG")
    print("  - AutoML Pipeline")
    print("\nUse individual functions or compile Kubeflow pipeline as needed.")
