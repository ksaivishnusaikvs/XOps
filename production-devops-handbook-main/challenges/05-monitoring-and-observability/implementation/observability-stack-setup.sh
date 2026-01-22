#!/bin/bash
#
# Complete Observability Stack Setup
# Deploys Prometheus, Grafana, Loki, and Jaeger on Kubernetes
#
# Usage: ./observability-stack-setup.sh
#

set -euo pipefail

NAMESPACE="observability"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log "Setting up complete observability stack..."

# Create namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repositories
log "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo update

# Install Prometheus
log "Installing Prometheus..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace "$NAMESPACE" \
    --set prometheus.prometheusSpec.retention=30d \
    --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
    --set alertmanager.enabled=true \
    --set grafana.enabled=true \
    --set grafana.adminPassword=admin \
    --wait

# Install Loki
log "Installing Loki..."
helm upgrade --install loki grafana/loki-stack \
    --namespace "$NAMESPACE" \
    --set loki.persistence.enabled=true \
    --set loki.persistence.size=10Gi \
    --set promtail.enabled=true \
    --wait

# Install Jaeger
log "Installing Jaeger..."
helm upgrade --install jaeger jaegertracing/jaeger \
    --namespace "$NAMESPACE" \
    --set provisionDataStore.cassandra=false \
    --set allInOne.enabled=true \
    --set storage.type=memory \
    --set query.enabled=true \
    --set collector.enabled=true \
    --set agent.enabled=true \
    --wait

log "✓ Observability stack installed successfully!"

# Get access information
cat <<EOF

========================================
Observability Stack Access Information
========================================

Grafana:
  kubectl port-forward -n $NAMESPACE svc/prometheus-grafana 3000:80
  URL: http://localhost:3000
  User: admin
  Password: admin

Prometheus:
  kubectl port-forward -n $NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090
  URL: http://localhost:9090

Alertmanager:
  kubectl port-forward -n $NAMESPACE svc/prometheus-kube-prometheus-alertmanager 9093:9093
  URL: http://localhost:9093

Loki:
  kubectl port-forward -n $NAMESPACE svc/loki 3100:3100
  URL: http://localhost:3100

Jaeger:
  kubectl port-forward -n $NAMESPACE svc/jaeger-query 16686:16686
  URL: http://localhost:16686

========================================
EOF
