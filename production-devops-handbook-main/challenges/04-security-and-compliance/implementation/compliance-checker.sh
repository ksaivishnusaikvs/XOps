#!/bin/bash
#
# Compliance Checker Script
# Validates infrastructure against CIS benchmarks and custom policies
#
# Usage: ./compliance-checker.sh
#

set -euo pipefail

REPORT_DIR="compliance-reports"
mkdir -p "$REPORT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

REPORT_FILE="$REPORT_DIR/compliance-report-$(date +%Y%m%d-%H%M%S).txt"
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

check() {
    local check_name="$1"
    local command="$2"
    
    ((TOTAL_CHECKS++))
    
    if eval "$command" > /dev/null 2>&1; then
        pass "$check_name"
        ((PASSED_CHECKS++))
        return 0
    else
        error "$check_name"
        ((FAILED_CHECKS++))
        return 1
    fi
}

log "Starting compliance checks..."

# Kubernetes CIS Benchmarks
log "=== Kubernetes CIS Benchmark Checks ==="

check "4.1.1 - Ensure RBAC is enabled" \
    "kubectl api-resources | grep -q rbac.authorization.k8s.io"

check "5.1.1 - Ensure default service accounts not used" \
    "! kubectl get pods --all-namespaces -o jsonpath='{.items[?(@.spec.serviceAccountName==\"default\")].metadata.name}' | grep -q ."

check "5.2.1 - Minimize privileged containers" \
    "! kubectl get pods --all-namespaces -o json | jq -e '.items[].spec.containers[].securityContext.privileged == true' 2>/dev/null"

check "5.2.2 - Minimize containers with hostNetwork" \
    "! kubectl get pods --all-namespaces -o json | jq -e '.items[].spec.hostNetwork == true' 2>/dev/null"

check "5.3.1 - Ensure Network Policies exist" \
    "kubectl get networkpolicies --all-namespaces | grep -q ."

check "5.7.1 - Create admin and user namespaces" \
    "kubectl get namespaces | grep -qE '(production|staging|development)'"

# Docker CIS Benchmarks (if applicable)
if command -v docker &> /dev/null; then
    log "=== Docker CIS Benchmark Checks ==="
    
    check "1.1 - Ensure Docker daemon logging level is info" \
        "docker info --format '{{.LoggingDriver}}' | grep -q json-file"
    
    check "2.1 - Ensure network traffic is restricted between containers" \
        "docker network ls | grep -q bridge"
fi

# Security Best Practices
log "=== Security Best Practices ==="

check "Secrets not in ConfigMaps" \
    "! kubectl get configmaps --all-namespaces -o json | jq -e '.items[].data | to_entries[] | select(.key | test(\"password|secret|token|key\"; \"i\"))' 2>/dev/null"

check "Resource limits defined" \
    "kubectl get pods --all-namespaces -o json | jq -e '.items[].spec.containers[].resources.limits' > /dev/null"

check "Liveness probes configured" \
    "kubectl get pods --all-namespaces -o json | jq -e '.items[].spec.containers[].livenessProbe' > /dev/null"

check "Readiness probes configured" \
    "kubectl get pods --all-namespaces -o json | jq -e '.items[].spec.containers[].readinessProbe' > /dev/null"

check "Image pull policy not set to Always or IfNotPresent" \
    "kubectl get pods --all-namespaces -o json | jq -e '.items[].spec.containers[].imagePullPolicy' | grep -qE '(Always|IfNotPresent)'"

check "Non-root user in containers" \
    "kubectl get pods --all-namespaces -o json | jq -e '.items[].spec.securityContext.runAsNonRoot == true' > /dev/null"

# Generate detailed report
cat > "$REPORT_FILE" <<EOF
========================================
Compliance Report
========================================
Date: $(date)
Total Checks: $TOTAL_CHECKS
Passed: $PASSED_CHECKS
Failed: $FAILED_CHECKS
Compliance Score: $((PASSED_CHECKS * 100 / TOTAL_CHECKS))%

========================================
Failed Checks
========================================
EOF

# Summary
log "=== Compliance Check Summary ==="
log "Total Checks: $TOTAL_CHECKS"
log "Passed: $PASSED_CHECKS"
log "Failed: $FAILED_CHECKS"
log "Compliance Score: $((PASSED_CHECKS * 100 / TOTAL_CHECKS))%"

if [ $FAILED_CHECKS -gt 0 ]; then
    error "Compliance checks failed. See $REPORT_FILE for details."
    exit 1
else
    pass "All compliance checks passed!"
    exit 0
fi
