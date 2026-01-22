#!/bin/bash
#
# Kubernetes Deployment Script with Safety Checks
# Performs gradual rollout with validation and automatic rollback
#
# Usage: ./k8s-deploy.sh <environment> <image-tag>
#

set -euo pipefail

ENVIRONMENT="${1:-staging}"
IMAGE_TAG="${2:-latest}"
NAMESPACE="$ENVIRONMENT"
APP_NAME="myapp"
DEPLOYMENT="$APP_NAME"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed"
    exit 1
fi

log "Starting deployment to $ENVIRONMENT"
log "Image tag: $IMAGE_TAG"

# Verify cluster connection
if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
    kubectl label namespace "$NAMESPACE" environment="$ENVIRONMENT"
fi

# Dry run first
log "Performing dry-run validation..."
if ! kubectl apply -f manifests/ --namespace="$NAMESPACE" --dry-run=client > /dev/null; then
    error "Dry-run validation failed"
    exit 1
fi

log "✓ Dry-run validation passed"

# Server-side dry run
log "Performing server-side validation..."
if ! kubectl apply -f manifests/ --namespace="$NAMESPACE" --dry-run=server > /dev/null; then
    error "Server-side validation failed"
    exit 1
fi

log "✓ Server-side validation passed"

# Save current state for rollback
CURRENT_IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "none")
log "Current image: $CURRENT_IMAGE"

# Update image tag
log "Updating deployment with new image..."
kubectl set image deployment/"$DEPLOYMENT" \
    app="$APP_NAME:$IMAGE_TAG" \
    --namespace="$NAMESPACE" \
    --record

# Watch rollout status
log "Monitoring rollout progress..."
if kubectl rollout status deployment/"$DEPLOYMENT" \
    --namespace="$NAMESPACE" \
    --timeout=5m; then
    log "✓ Rollout completed successfully"
else
    error "Rollout failed or timed out"
    
    # Automatic rollback
    warning "Initiating automatic rollback..."
    kubectl rollout undo deployment/"$DEPLOYMENT" --namespace="$NAMESPACE"
    
    if kubectl rollout status deployment/"$DEPLOYMENT" --namespace="$NAMESPACE" --timeout=3m; then
        log "✓ Rollback completed"
    else
        error "Rollback failed - manual intervention required!"
    fi
    
    exit 1
fi

# Post-deployment validation
log "Running post-deployment validation..."

# Check pod health
READY_PODS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
DESIRED_PODS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')

if [ "$READY_PODS" != "$DESIRED_PODS" ]; then
    error "Not all pods are ready ($READY_PODS/$DESIRED_PODS)"
    
    log "Pod status:"
    kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME"
    
    log "Recent events:"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
    
    exit 1
fi

log "✓ All pods are healthy ($READY_PODS/$DESIRED_PODS)"

# Test endpoint health
SERVICE_URL=$(kubectl get ingress "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

if [ -n "$SERVICE_URL" ]; then
    log "Testing endpoint: https://$SERVICE_URL/health"
    
    if curl -sf "https://$SERVICE_URL/health" > /dev/null; then
        log "✓ Health check passed"
    else
        warning "Health check failed - but deployment is complete"
    fi
fi

# Deployment summary
cat <<EOF

========================================
Deployment Summary
========================================
Environment: $ENVIRONMENT
Namespace: $NAMESPACE
Application: $APP_NAME
Previous Image: $CURRENT_IMAGE
New Image: $APP_NAME:$IMAGE_TAG
Ready Pods: $READY_PODS/$DESIRED_PODS
Status: SUCCESS
========================================

EOF

log "Deployment completed successfully!"
