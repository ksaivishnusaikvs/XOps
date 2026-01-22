# AI/ML/LLM Operations - Complete Implementation Guide

## Step 1: Set Up MLflow Tracking Server

### 1.1 Deploy MLflow on Kubernetes
```bash
# Create namespace
kubectl create namespace mlflow

# Deploy PostgreSQL for MLflow backend
helm install mlflow-postgres bitnami/postgresql \
  --namespace mlflow \
  --set auth.database=mlflow \
  --set auth.username=mlflow \
  --set auth.password=mlflow123

# Deploy MinIO for artifact storage
helm install mlflow-minio bitnami/minio \
  --namespace mlflow \
  --set auth.rootUser=minio \
  --set auth.rootPassword=minio123 \
  --set defaultBuckets=mlflow

# Deploy MLflow server
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-server
  namespace: mlflow
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mlflow
  template:
    metadata:
      labels:
        app: mlflow
    spec:
      containers:
      - name: mlflow
        image: python:3.9-slim
        command:
          - sh
          - -c
          - |
            pip install mlflow boto3 psycopg2-binary
            mlflow server \
              --backend-store-uri postgresql://mlflow:mlflow123@mlflow-postgres:5432/mlflow \
              --default-artifact-root s3://mlflow/artifacts \
              --host 0.0.0.0 \
              --port 5000
        env:
        - name: AWS_ACCESS_KEY_ID
          value: "minio"
        - name: AWS_SECRET_ACCESS_KEY
          value: "minio123"
        - name: MLFLOW_S3_ENDPOINT_URL
          value: "http://mlflow-minio:9000"
        ports:
        - containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow-server
  namespace: mlflow
spec:
  selector:
    app: mlflow
  ports:
  - port: 5000
    targetPort: 5000
EOF
```

### 1.2 Access MLflow UI
```bash
kubectl port-forward -n mlflow svc/mlflow-server 5000:5000
# Open http://localhost:5000
```

## Step 2: Set Up Kubeflow Pipelines

### 2.1 Install Kubeflow Pipelines
```bash
export PIPELINE_VERSION=2.0.3
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=$PIPELINE_VERSION"
```

### 2.2 Access Kubeflow UI
```bash
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80
# Open http://localhost:8080
```

### 2.3 Install Kubeflow SDK
```bash
pip install kfp==2.0.3
```

## Step 3: Create ML Training Pipeline

### 3.1 Create Training Script
```python
# training/train_model.py
import argparse
import mlflow
import mlflow.sklearn
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, precision_score, recall_score

def train_model(n_estimators=100, max_depth=10):
    """Train ML model with MLflow tracking"""
    
    # Set MLflow tracking URI
    mlflow.set_tracking_uri("http://mlflow-server.mlflow:5000")
    mlflow.set_experiment("iris-classification")
    
    with mlflow.start_run():
        # Load data
        X, y = load_iris(return_X_y=True)
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        
        # Train model
        model = RandomForestClassifier(
            n_estimators=n_estimators,
            max_depth=max_depth,
            random_state=42
        )
        model.fit(X_train, y_train)
        
        # Evaluate
        y_pred = model.predict(X_test)
        accuracy = accuracy_score(y_test, y_pred)
        precision = precision_score(y_test, y_pred, average='weighted')
        recall = recall_score(y_test, y_pred, average='weighted')
        
        # Log parameters
        mlflow.log_param("n_estimators", n_estimators)
        mlflow.log_param("max_depth", max_depth)
        
        # Log metrics
        mlflow.log_metric("accuracy", accuracy)
        mlflow.log_metric("precision", precision)
        mlflow.log_metric("recall", recall)
        
        # Log model
        mlflow.sklearn.log_model(model, "model")
        
        print(f"Model trained with accuracy: {accuracy:.4f}")
        
        return model

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--n-estimators", type=int, default=100)
    parser.add_argument("--max-depth", type=int, default=10)
    args = parser.parse_args()
    
    train_model(args.n_estimators, args.max_depth)
```

### 3.2 Run Training Job
```bash
python training/train_model.py --n-estimators 200 --max-depth 15
```

## Step 4: Deploy Model with KServe

### 4.1 Install KServe
```bash
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve-runtimes.yaml
```

### 4.2 Create Model Serving Deployment
```yaml
# model-serving.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: iris-classifier
  namespace: ml-serving
spec:
  predictor:
    serviceAccountName: default
    model:
      modelFormat:
        name: sklearn
      storageUri: "s3://mlflow/artifacts/1/model"
      resources:
        limits:
          cpu: "1"
          memory: 2Gi
        requests:
          cpu: "100m"
          memory: 512Mi
    minReplicas: 1
    maxReplicas: 5
    scaleTarget: 80
```

```bash
kubectl apply -f model-serving.yaml
```

### 4.3 Test Model Inference
```bash
# Get inference URL
INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
SERVICE_HOSTNAME=$(kubectl get inferenceservice iris-classifier -n ml-serving -o jsonpath='{.status.url}' | cut -d "/" -f 3)

# Make prediction
curl -H "Host: ${SERVICE_HOSTNAME}" \
  -H "Content-Type: application/json" \
  http://${INGRESS_HOST}/v1/models/iris-classifier:predict \
  -d '{
    "instances": [
      [5.1, 3.5, 1.4, 0.2],
      [6.2, 2.9, 4.3, 1.3]
    ]
  }'
```

## Step 5: Set Up LLM Deployment

### 5.1 Deploy LLM with vLLM
```yaml
# llm-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-server
  namespace: ml-serving
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llm-server
  template:
    metadata:
      labels:
        app: llm-server
    spec:
      containers:
      - name: vllm
        image: vllm/vllm-openai:latest
        command:
          - python3
          - -m
          - vllm.entrypoints.openai.api_server
          - --model
          - gpt2
          - --port
          - "8000"
        resources:
          limits:
            nvidia.com/gpu: "1"
            memory: 16Gi
          requests:
            nvidia.com/gpu: "1"
            memory: 8Gi
        ports:
        - containerPort: 8000
---
apiVersion: v1
kind: Service
metadata:
  name: llm-server
  namespace: ml-serving
spec:
  selector:
    app: llm-server
  ports:
  - port: 8000
    targetPort: 8000
  type: LoadBalancer
```

### 5.2 Use LLM API
```python
import openai

# Configure client
openai.api_base = "http://llm-server.ml-serving:8000/v1"
openai.api_key = "dummy"  # vLLM doesn't require auth

# Generate text
response = openai.Completion.create(
    model="gpt2",
    prompt="Explain machine learning in simple terms:",
    max_tokens=100,
    temperature=0.7
)

print(response.choices[0].text)
```

## Step 6: Implement Model Monitoring

### 6.1 Install Evidently
```bash
pip install evidently
```

### 6.2 Create Monitoring Dashboard
```python
# monitoring/model_monitoring.py
from evidently import ColumnMapping
from evidently.report import Report
from evidently.metrics import (
    DataDriftPreset,
    DataQualityPreset,
    RegressionPreset
)
import pandas as pd

def create_monitoring_report(
    reference_data: pd.DataFrame,
    current_data: pd.DataFrame
):
    """Create data drift monitoring report"""
    
    column_mapping = ColumnMapping(
        target='target',
        prediction='prediction',
        numerical_features=['feature1', 'feature2'],
    )
    
    report = Report(metrics=[
        DataDriftPreset(),
        DataQualityPreset(),
        RegressionPreset()
    ])
    
    report.run(
        reference_data=reference_data,
        current_data=current_data,
        column_mapping=column_mapping
    )
    
    report.save_html("monitoring_report.html")
    
    return report

# Schedule monitoring
from apscheduler.schedulers.background import BackgroundScheduler

scheduler = BackgroundScheduler()
scheduler.add_job(
    create_monitoring_report,
    'interval',
    hours=6,
    args=[reference_df, current_df]
)
scheduler.start()
```

## Step 7: Implement RAG System

### 7.1 Set Up Vector Database (Weaviate)
```bash
helm repo add weaviate https://weaviate.github.io/weaviate-helm
helm install weaviate weaviate/weaviate \
  --namespace ml-serving \
  --set replicas=1
```

### 7.2 Create RAG Pipeline
```python
# rag/rag_pipeline.py
from langchain.vectorstores import Weaviate
from langchain.embeddings import OpenAIEmbeddings
from langchain.chat_models import ChatOpenAI
from langchain.chains import RetrievalQA
from langchain.text_splitter import RecursiveCharacterTextSplitter
import weaviate

# Initialize Weaviate client
client = weaviate.Client(
    url="http://weaviate.ml-serving:8080"
)

def ingest_documents(documents: list[str]):
    """Ingest documents into vector store"""
    
    # Split documents
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200
    )
    texts = text_splitter.create_documents(documents)
    
    # Create embeddings
    embeddings = OpenAIEmbeddings()
    
    # Store in Weaviate
    vectorstore = Weaviate.from_documents(
        texts,
        embeddings,
        client=client,
        index_name="Documents"
    )
    
    return vectorstore

def create_rag_chain():
    """Create RAG question-answering chain"""
    
    embeddings = OpenAIEmbeddings()
    vectorstore = Weaviate(
        client=client,
        index_name="Documents",
        text_key="text",
        embedding=embeddings
    )
    
    # Create QA chain
    qa_chain = RetrievalQA.from_chain_type(
        llm=ChatOpenAI(model="gpt-3.5-turbo"),
        chain_type="stuff",
        retriever=vectorstore.as_retriever(search_kwargs={"k": 3}),
        return_source_documents=True
    )
    
    return qa_chain

# Usage
qa_chain = create_rag_chain()
result = qa_chain({"query": "What is machine learning?"})
print(result['result'])
```

## Step 8: Implement Model Versioning

### 8.1 Register Model in MLflow
```python
import mlflow
from mlflow.tracking import MlflowClient

# Register model
mlflow.set_tracking_uri("http://mlflow-server.mlflow:5000")
client = MlflowClient()

# Create or get registered model
try:
    client.create_registered_model("iris-classifier")
except:
    pass

# Create new version
model_uri = "runs:/abc123/model"
mv = client.create_model_version(
    name="iris-classifier",
    source=model_uri,
    run_id="abc123"
)

# Transition to production
client.transition_model_version_stage(
    name="iris-classifier",
    version=mv.version,
    stage="Production"
)
```

### 8.2 Load Model by Stage
```python
import mlflow.sklearn

# Load production model
model = mlflow.sklearn.load_model("models:/iris-classifier/Production")

# Make prediction
prediction = model.predict([[5.1, 3.5, 1.4, 0.2]])
```

## Step 9: GPU Resource Management

### 9.1 Install NVIDIA GPU Operator
```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm install --wait --generate-name \
  -n gpu-operator --create-namespace \
  nvidia/gpu-operator
```

### 9.2 Configure GPU Sharing
```yaml
# gpu-sharing-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gpu-sharing-config
  namespace: kube-system
data:
  gpu-sharing.conf: |
    version: v1
    sharing:
      timeSlicing:
        replicas: 4
```

### 9.3 Use GPU in Deployment
```yaml
resources:
  limits:
    nvidia.com/gpu: "1"
  requests:
    nvidia.com/gpu: "1"
```

## Step 10: Cost Optimization

### 10.1 Use Spot Instances for Training
```yaml
# training-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: ml-training-job
spec:
  template:
    spec:
      nodeSelector:
        cloud.google.com/gke-spot: "true"  # For GKE
        # Or for AWS:
        # eks.amazonaws.com/capacityType: SPOT
      containers:
      - name: training
        image: my-training-image:latest
        resources:
          limits:
            nvidia.com/gpu: "1"
      restartPolicy: Never
```

### 10.2 Model Quantization
```python
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

# Load model
model = AutoModelForCausalLM.from_pretrained("gpt2")

# Quantize to int8
quantized_model = torch.quantization.quantize_dynamic(
    model, {torch.nn.Linear}, dtype=torch.qint8
)

# Save quantized model
quantized_model.save_pretrained("gpt2-quantized")
```

## MLOps/LLMOps Checklist

- [ ] MLflow tracking server deployed
- [ ] Kubeflow pipelines configured
- [ ] Model registry implemented
- [ ] Model serving with KServe
- [ ] LLM deployment configured
- [ ] Vector database for RAG
- [ ] Model monitoring implemented
- [ ] A/B testing capability
- [ ] GPU resource management
- [ ] Cost optimization strategies
- [ ] Model versioning workflow
- [ ] Automated retraining pipeline
