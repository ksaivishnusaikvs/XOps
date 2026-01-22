#!/bin/bash
# Blue-Green Deployment Script for Jenkins Pipeline
# This script manages zero-downtime deployments using blue-green strategy

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

APP_NAME="${1:-myapp}"
VERSION="${2:-latest}"
NAMESPACE="${APP_NAME}-production"
KUBECTL="kubectl"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# Blue-Green Deployment Functions
# ============================================================================

get_current_environment() {
    # Get current active environment (blue or green)
    local selector=$(${KUBECTL} get service ${APP_NAME} -n ${NAMESPACE} \
        -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "blue")
    echo "${selector}"
}

get_target_environment() {
    local current=$1
    if [[ "${current}" == "blue" ]]; then
        echo "green"
    else
        echo "blue"
    fi
}

deploy_to_target() {
    local target_env=$1
    local version=$2
    
    log_info "Deploying ${APP_NAME}:${version} to ${target_env} environment"
    
    # Apply deployment
    cat <<EOF | ${KUBECTL} apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}-${target_env}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    version: ${target_env}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ${APP_NAME}
      version: ${target_env}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        version: ${target_env}
    spec:
      containers:
      - name: ${APP_NAME}
        image: docker.company.com/${APP_NAME}:${version}
        ports:
        - containerPort: 8080
        env:
        - name: ENVIRONMENT
          value: ${target_env}
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
EOF
    
    log_success "Deployment applied to ${target_env}"
}

wait_for_deployment() {
    local target_env=$1
    
    log_info "Waiting for ${target_env} deployment to be ready..."
    
    if ${KUBECTL} rollout status deployment/${APP_NAME}-${target_env} \
        -n ${NAMESPACE} --timeout=300s; then
        log_success "${target_env} deployment is ready"
        return 0
    else
        log_error "${target_env} deployment failed to become ready"
        return 1
    fi
}

run_smoke_tests() {
    local target_env=$1
    
    log_info "Running smoke tests against ${target_env} environment"
    
    # Get pod IP for direct testing
    local pod_ip=$(${KUBECTL} get pods -n ${NAMESPACE} \
        -l app=${APP_NAME},version=${target_env} \
        -o jsonpath='{.items[0].status.podIP}')
    
    if [[ -z "${pod_ip}" ]]; then
        log_error "Could not get pod IP for smoke tests"
        return 1
    fi
    
    # Run health check
    if ${KUBECTL} run smoke-test-${RANDOM} --rm -i --restart=Never \
        --image=curlimages/curl:latest \
        -n ${NAMESPACE} \
        -- curl -f -m 10 "http://${pod_ip}:8080/health" > /dev/null 2>&1; then
        log_success "Health check passed"
    else
        log_error "Health check failed"
        return 1
    fi
    
    # Run API test
    if ${KUBECTL} run api-test-${RANDOM} --rm -i --restart=Never \
        --image=curlimages/curl:latest \
        -n ${NAMESPACE} \
        -- curl -f -m 10 "http://${pod_ip}:8080/api/status" > /dev/null 2>&1; then
        log_success "API test passed"
    else
        log_error "API test failed"
        return 1
    fi
    
    log_success "All smoke tests passed"
    return 0
}

switch_traffic() {
    local target_env=$1
    
    log_info "Switching traffic to ${target_env} environment"
    
    # Update service selector
    ${KUBECTL} patch service ${APP_NAME} -n ${NAMESPACE} \
        -p "{\"spec\":{\"selector\":{\"version\":\"${target_env}\"}}}"
    
    log_success "Traffic switched to ${target_env}"
    
    # Wait for service to update
    sleep 5
}

verify_traffic_switch() {
    local target_env=$1
    
    log_info "Verifying traffic switch to ${target_env}"
    
    # Get service endpoint
    local service_url="http://${APP_NAME}.${NAMESPACE}.svc.cluster.local:8080"
    
    # Test traffic
    local test_count=5
    local success_count=0
    
    for i in $(seq 1 ${test_count}); do
        if ${KUBECTL} run traffic-test-${RANDOM} --rm -i --restart=Never \
            --image=curlimages/curl:latest \
            -n ${NAMESPACE} \
            -- curl -f -m 10 "${service_url}/health" > /dev/null 2>&1; then
            ((success_count++))
        fi
        sleep 2
    done
    
    if [[ ${success_count} -eq ${test_count} ]]; then
        log_success "Traffic verification passed (${success_count}/${test_count})"
        return 0
    else
        log_error "Traffic verification failed (${success_count}/${test_count})"
        return 1
    fi
}

cleanup_old_environment() {
    local old_env=$1
    
    log_info "Cleaning up old ${old_env} environment"
    
    # Scale down old deployment
    ${KUBECTL} scale deployment/${APP_NAME}-${old_env} \
        -n ${NAMESPACE} --replicas=0
    
    log_success "Scaled down ${old_env} environment"
}

rollback() {
    local current_env=$1
    local target_env=$2
    
    log_warning "Rolling back to ${current_env} environment"
    
    # Switch traffic back
    switch_traffic "${current_env}"
    
    # Delete failed deployment
    ${KUBECTL} delete deployment/${APP_NAME}-${target_env} \
        -n ${NAMESPACE} --ignore-not-found=true
    
    log_error "Rollback completed"
}

# ============================================================================
# Main Deployment Logic
# ============================================================================

main() {
    log_info "Starting Blue-Green deployment for ${APP_NAME}:${VERSION}"
    
    # Determine current and target environments
    CURRENT_ENV=$(get_current_environment)
    TARGET_ENV=$(get_target_environment "${CURRENT_ENV}")
    
    log_info "Current environment: ${CURRENT_ENV}"
    log_info "Target environment: ${TARGET_ENV}"
    
    # Deploy to target environment
    if ! deploy_to_target "${TARGET_ENV}" "${VERSION}"; then
        log_error "Deployment to ${TARGET_ENV} failed"
        exit 1
    fi
    
    # Wait for deployment to be ready
    if ! wait_for_deployment "${TARGET_ENV}"; then
        log_error "Target deployment not ready"
        cleanup_old_environment "${TARGET_ENV}"
        exit 1
    fi
    
    # Run smoke tests
    if ! run_smoke_tests "${TARGET_ENV}"; then
        log_error "Smoke tests failed"
        rollback "${CURRENT_ENV}" "${TARGET_ENV}"
        exit 1
    fi
    
    # Switch traffic to target environment
    switch_traffic "${TARGET_ENV}"
    
    # Verify traffic switch
    if ! verify_traffic_switch "${TARGET_ENV}"; then
        log_error "Traffic verification failed"
        rollback "${CURRENT_ENV}" "${TARGET_ENV}"
        exit 1
    fi
    
    # Cleanup old environment
    cleanup_old_environment "${CURRENT_ENV}"
    
    log_success "Blue-Green deployment completed successfully!"
    log_success "Active environment: ${TARGET_ENV}"
    log_success "Version deployed: ${VERSION}"
}

# ============================================================================
# Script Execution
# ============================================================================

# Validate arguments
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <app-name> <version>"
    exit 1
fi

# Execute main function
main
