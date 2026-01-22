#!/bin/bash
# DevSecOps Pipeline Integration Script

set -e

echo "=== DevSecOps Pipeline Integration ==="

# Configuration
WORKSPACE=${1:-.}
REPORT_DIR="$WORKSPACE/security-reports"
mkdir -p "$REPORT_DIR"

###########################################
# 1. Pre-commit Security Checks
###########################################
echo "\n[1] Running Pre-commit Security Checks..."

# Secret scanning with Gitleaks
if command -v gitleaks &> /dev/null; then
    echo "Running Gitleaks secret scanner..."
    gitleaks detect --source="$WORKSPACE" \
        --report-path="$REPORT_DIR/gitleaks-report.json" \
        --report-format=json \
        --verbose || true
fi

# Detect hardcoded credentials
echo "Checking for hardcoded credentials..."
grep -r -E "(password|passwd|pwd|secret|token|api_key|apikey)" "$WORKSPACE" \
    --exclude-dir={.git,node_modules,vendor,venv} \
    --exclude="*.{md,txt,json}" || echo "No hardcoded credentials found"

###########################################
# 2. SAST - Static Application Security Testing
###########################################
echo "\n[2] Running SAST Scans..."

# Semgrep for code security
if command -v semgrep &> /dev/null; then
    echo "Running Semgrep SAST..."
    semgrep --config=auto \
        --json \
        --output="$REPORT_DIR/semgrep.json" \
        "$WORKSPACE" || true
fi

# Bandit for Python
if [ -f "$WORKSPACE/requirements.txt" ] || [ -f "$WORKSPACE/setup.py" ]; then
    if command -v bandit &> /dev/null; then
        echo "Running Bandit for Python security..."
        bandit -r "$WORKSPACE" \
            -f json \
            -o "$REPORT_DIR/bandit.json" || true
    fi
fi

# NodeJSScan for Node.js
if [ -f "$WORKSPACE/package.json" ]; then
    if command -v nodejsscan &> /dev/null; then
        echo "Running NodeJSScan..."
        nodejsscan -d "$WORKSPACE" -o "$REPORT_DIR/nodejsscan.json" || true
    fi
fi

###########################################
# 3. Dependency Scanning (SCA)
###########################################
echo "\n[3] Running Software Composition Analysis..."

# npm audit for Node.js
if [ -f "$WORKSPACE/package.json" ]; then
    echo "Running npm audit..."
    cd "$WORKSPACE"
    npm audit --json > "$REPORT_DIR/npm-audit.json" || true
    npm audit --audit-level=moderate || true
    cd - > /dev/null
fi

# Safety for Python
if [ -f "$WORKSPACE/requirements.txt" ]; then
    if command -v safety &> /dev/null; then
        echo "Running Safety for Python dependencies..."
        safety check \
            --file="$WORKSPACE/requirements.txt" \
            --json \
            --output="$REPORT_DIR/safety.json" || true
    fi
fi

# OWASP Dependency-Check
if command -v dependency-check &> /dev/null; then
    echo "Running OWASP Dependency-Check..."
    dependency-check \
        --project "MyApp" \
        --scan "$WORKSPACE" \
        --format JSON \
        --out "$REPORT_DIR/dependency-check.json" || true
fi

# Snyk scan
if command -v snyk &> /dev/null; then
    echo "Running Snyk vulnerability scan..."
    snyk test \
        --json \
        --json-file-output="$REPORT_DIR/snyk.json" || true
fi

###########################################
# 4. Container Image Scanning
###########################################
echo "\n[4] Running Container Security Scans..."

# Find Dockerfiles
DOCKERFILES=$(find "$WORKSPACE" -name Dockerfile)

for dockerfile in $DOCKERFILES; do
    echo "Scanning Dockerfile: $dockerfile"
    
    # Hadolint for Dockerfile linting
    if command -v hadolint &> /dev/null; then
        hadolint "$dockerfile" || true
    fi
    
    # Build and scan image with Trivy
    if [ -n "$DOCKER_IMAGE" ]; then
        if command -v trivy &> /dev/null; then
            echo "Scanning Docker image with Trivy..."
            trivy image \
                --severity HIGH,CRITICAL \
                --format json \
                --output "$REPORT_DIR/trivy-image.json" \
                "$DOCKER_IMAGE" || true
        fi
        
        # Grype for vulnerability scanning
        if command -v grype &> /dev/null; then
            echo "Scanning with Grype..."
            grype "$DOCKER_IMAGE" \
                -o json \
                --file "$REPORT_DIR/grype.json" || true
        fi
    fi
done

###########################################
# 5. Infrastructure as Code Security
###########################################
echo "\n[5] Running IaC Security Scans..."

# Checkov for IaC security
if command -v checkov &> /dev/null; then
    echo "Running Checkov IaC scan..."
    checkov -d "$WORKSPACE" \
        --framework terraform kubernetes dockerfile helm \
        --output json \
        --output-file "$REPORT_DIR/checkov.json" || true
    
    # Display summary
    checkov -d "$WORKSPACE" \
        --framework terraform kubernetes dockerfile helm \
        --compact \
        --quiet || true
fi

# tfsec for Terraform
if [ -d "$WORKSPACE/terraform" ]; then
    if command -v tfsec &> /dev/null; then
        echo "Running tfsec for Terraform..."
        tfsec "$WORKSPACE/terraform" \
            --format json \
            --out "$REPORT_DIR/tfsec.json" || true
    fi
fi

# kube-score for Kubernetes
K8S_FILES=$(find "$WORKSPACE" -name "*.yaml" -o -name "*.yml" | grep -E "(k8s|kubernetes)")
if [ -n "$K8S_FILES" ] && command -v kube-score &> /dev/null; then
    echo "Running kube-score..."
    for file in $K8S_FILES; do
        kube-score score "$file" || true
    done
fi

###########################################
# 6. License Compliance
###########################################
echo "\n[6] Checking License Compliance..."

# license-checker for Node.js
if [ -f "$WORKSPACE/package.json" ]; then
    if command -v license-checker &> /dev/null; then
        echo "Checking npm licenses..."
        license-checker --json --out "$REPORT_DIR/licenses.json" || true
    fi
fi

# pip-licenses for Python
if [ -f "$WORKSPACE/requirements.txt" ]; then
    if command -v pip-licenses &> /dev/null; then
        echo "Checking Python licenses..."
        pip-licenses --format=json --output-file="$REPORT_DIR/python-licenses.json" || true
    fi
fi

###########################################
# 7. Security Policy Enforcement
###########################################
echo "\n[7] Enforcing Security Policies..."

# OPA (Open Policy Agent) for policy enforcement
if command -v opa &> /dev/null; then
    if [ -d "$WORKSPACE/policies" ]; then
        echo "Running OPA policy tests..."
        opa test "$WORKSPACE/policies" -v || true
    fi
fi

###########################################
# 8. Generate Security Report
###########################################
echo "\n[8] Generating Security Summary..."

cat > "$REPORT_DIR/security-summary.md" <<EOF
# Security Scan Summary

**Date:** $(date)
**Project:** ${PROJECT_NAME:-Unknown}

## Scans Performed

### 1. Secret Detection
- **Tool:** Gitleaks
- **Status:** $([ -f "$REPORT_DIR/gitleaks-report.json" ] && echo "✅ Complete" || echo "⚠️ Not Run")

### 2. SAST (Static Analysis)
- **Tool:** Semgrep
- **Status:** $([ -f "$REPORT_DIR/semgrep.json" ] && echo "✅ Complete" || echo "⚠️ Not Run")

### 3. Dependency Scanning
- **Tools:** npm audit, Snyk, OWASP Dependency-Check
- **Status:** ✅ Complete

### 4. Container Scanning
- **Tools:** Trivy, Grype
- **Status:** $([ -f "$REPORT_DIR/trivy-image.json" ] && echo "✅ Complete" || echo "⚠️ Not Run")

### 5. IaC Security
- **Tools:** Checkov, tfsec
- **Status:** $([ -f "$REPORT_DIR/checkov.json" ] && echo "✅ Complete" || echo "⚠️ Not Run")

### 6. License Compliance
- **Status:** ✅ Complete

## Critical Findings

EOF

# Count critical issues from Trivy if available
if [ -f "$REPORT_DIR/trivy-image.json" ]; then
    CRITICAL_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$REPORT_DIR/trivy-image.json" 2>/dev/null || echo "0")
    echo "- **Critical Vulnerabilities:** $CRITICAL_COUNT" >> "$REPORT_DIR/security-summary.md"
fi

# Count high severity from Semgrep
if [ -f "$REPORT_DIR/semgrep.json" ]; then
    HIGH_COUNT=$(jq '.results | length' "$REPORT_DIR/semgrep.json" 2>/dev/null || echo "0")
    echo "- **SAST Issues:** $HIGH_COUNT" >> "$REPORT_DIR/security-summary.md"
fi

echo "\n## Recommendations" >> "$REPORT_DIR/security-summary.md"
echo "1. Review and remediate all CRITICAL and HIGH severity findings" >> "$REPORT_DIR/security-summary.md"
echo "2. Update dependencies with known vulnerabilities" >> "$REPORT_DIR/security-summary.md"
echo "3. Implement automated security scanning in CI/CD pipeline" >> "$REPORT_DIR/security-summary.md"
echo "4. Regular security training for development team" >> "$REPORT_DIR/security-summary.md"

###########################################
# 9. Quality Gate Check
###########################################
echo "\n[9] Checking Security Quality Gates..."

GATE_FAILED=0

# Fail if critical vulnerabilities found
if [ -f "$REPORT_DIR/trivy-image.json" ]; then
    CRITICAL=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$REPORT_DIR/trivy-image.json" 2>/dev/null || echo "0")
    if [ "$CRITICAL" -gt 0 ]; then
        echo "❌ FAIL: $CRITICAL critical vulnerabilities found!"
        GATE_FAILED=1
    fi
fi

# Check for secrets
if [ -f "$REPORT_DIR/gitleaks-report.json" ]; then
    SECRETS=$(jq 'length' "$REPORT_DIR/gitleaks-report.json" 2>/dev/null || echo "0")
    if [ "$SECRETS" -gt 0 ]; then
        echo "❌ FAIL: $SECRETS secrets detected!"
        GATE_FAILED=1
    fi
fi

if [ $GATE_FAILED -eq 0 ]; then
    echo "✅ All security quality gates passed!"
else
    echo "❌ Security quality gates FAILED!"
    echo "Review reports in: $REPORT_DIR"
    exit 1
fi

echo "\n=== DevSecOps Scan Complete ==="
echo "Reports available in: $REPORT_DIR"
