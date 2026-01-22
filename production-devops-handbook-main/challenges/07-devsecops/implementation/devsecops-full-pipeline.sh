#!/bin/bash
#
# Comprehensive DevSecOps Security Pipeline
# Integrates security at every stage of the development pipeline
#
# Usage: ./devsecops-full-pipeline.sh
#

set -euo pipefail

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

SECURITY_PASSED=true

log "Starting DevSecOps Pipeline..."

# Stage 1: Pre-commit checks
log "=== Stage 1: Pre-commit Security Checks ==="

if [ -f ".pre-commit-config.yaml" ]; then
    log "Running pre-commit hooks..."
    pre-commit run --all-files || SECURITY_PASSED=false
else
    warning "Pre-commit not configured"
fi

# Stage 2: Secret Scanning
log "=== Stage 2: Secret Detection ==="

if command -v gitleaks &> /dev/null; then
    log "Scanning for secrets with Gitleaks..."
    if ! gitleaks detect --source . --no-git; then
        error "Secrets detected!"
        SECURITY_PASSED=false
    fi
else
    warning "Gitleaks not installed"
fi

# Stage 3: SAST (Static Application Security Testing)
log "=== Stage 3: SAST Analysis ==="

if command -v semgrep &> /dev/null; then
    log "Running Semgrep SAST scan..."
    if ! semgrep --config auto --error --quiet .; then
        error "SAST scan found vulnerabilities"
        SECURITY_PASSED=false
    fi
else
    warning "Semgrep not installed"
fi

# Stage 4: Dependency Scanning
log "=== Stage 4: Dependency Vulnerability Scan ==="

if [ -f "package.json" ]; then
    log "Checking npm dependencies..."
    npm audit --audit-level=high || SECURITY_PASSED=false
fi

if [ -f "requirements.txt" ]; then
    log "Checking Python dependencies..."
    safety check || SECURITY_PASSED=false
fi

# Stage 5: IaC Security Scanning
log "=== Stage 5: Infrastructure as Code Security ==="

if command -v checkov &> /dev/null; then
    log "Scanning IaC with Checkov..."
    if ! checkov -d . --quiet --compact --framework terraform kubernetes dockerfile; then
        error "IaC security issues found"
        SECURITY_PASSED=false
    fi
else
    warning "Checkov not installed"
fi

# Stage 6: Container Image Scanning
log "=== Stage 6: Container Security Scan ==="

if [ -f "Dockerfile" ] && command -v trivy &> /dev/null; then
    log "Building and scanning container image..."
    docker build -t security-scan:latest . || SECURITY_PASSED=false
    
    if ! trivy image --severity HIGH,CRITICAL --exit-code 1 security-scan:latest; then
        error "Container vulnerabilities found"
        SECURITY_PASSED=false
    fi
    
    docker rmi security-scan:latest || true
else
    warning "Dockerfile not found or Trivy not installed"
fi

# Stage 7: License Compliance
log "=== Stage 7: License Compliance Check ==="

if command -v license-checker &> /dev/null && [ -f "package.json" ]; then
    log "Checking license compliance..."
    license-checker --onlyAllow 'MIT;Apache-2.0;BSD-3-Clause;ISC' || warning "License check failed"
fi

# Stage 8: Security Report Generation
log "=== Stage 8: Generating Security Report ==="

cat > security-report.txt <<EOF
DevSecOps Pipeline Report
========================
Date: $(date)
Status: $([ "$SECURITY_PASSED" = true ] && echo "PASSED" || echo "FAILED")

Checks Performed:
- Pre-commit hooks
- Secret detection
- SAST analysis
- Dependency vulnerabilities
- IaC security
- Container scanning
- License compliance

Next Steps:
$([ "$SECURITY_PASSED" = true ] && echo "✓ All checks passed - ready for deployment" || echo "✗ Fix security issues before deployment")

EOF

cat security-report.txt

# Final result
if [ "$SECURITY_PASSED" = true ]; then
    log "✓ DevSecOps pipeline completed successfully"
    exit 0
else
    error "✗ DevSecOps pipeline failed - security issues detected"
    exit 1
fi
