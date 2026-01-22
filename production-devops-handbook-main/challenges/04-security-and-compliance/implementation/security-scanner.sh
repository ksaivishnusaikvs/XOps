#!/bin/bash
#
# Comprehensive Security Scanner for IaC and Containers
# Runs multiple security tools: Trivy, Checkov, Semgrep, Gitleaks
#
# Usage: ./security-scanner.sh [options]
#

set -euo pipefail

# Configuration
SCAN_TYPE="${SCAN_TYPE:-all}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-table}"
FAIL_ON_SEVERITY="${FAIL_ON_SEVERITY:-CRITICAL}"
REPORT_DIR="security-reports"

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

# Create reports directory
mkdir -p "$REPORT_DIR"

REPORT_FILE="$REPORT_DIR/security-report-$(date +%Y%m%d-%H%M%S).txt"
ISSUES_FOUND=0

log "Starting comprehensive security scan..."

# Function to check if tool is installed
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        warning "$1 is not installed. Skipping $1 scan."
        return 1
    fi
    return 0
}

# 1. Scan Infrastructure as Code with Checkov
scan_iac_checkov() {
    log "Running Checkov scan on Infrastructure as Code..."
    
    if check_tool checkov; then
        checkov -d . \
            --framework terraform kubernetes helm dockerfile \
            --output cli \
            --soft-fail \
            --compact \
            > "$REPORT_DIR/checkov-report.txt" 2>&1 || true
        
        CHECKOV_ISSUES=$(grep -c "Check:" "$REPORT_DIR/checkov-report.txt" || echo "0")
        log "Checkov found $CHECKOV_ISSUES issues"
        ((ISSUES_FOUND += CHECKOV_ISSUES))
    fi
}

# 2. Scan containers with Trivy
scan_containers_trivy() {
    log "Running Trivy container scan..."
    
    if check_tool trivy; then
        # Find Dockerfiles
        find . -name "Dockerfile*" -type f | while read -r dockerfile; do
            log "Scanning $dockerfile"
            
            # Build image for scanning
            IMAGE_NAME="security-scan:$(basename $dockerfile)"
            docker build -f "$dockerfile" -t "$IMAGE_NAME" . > /dev/null 2>&1 || continue
            
            # Scan image
            trivy image \
                --severity HIGH,CRITICAL \
                --format table \
                "$IMAGE_NAME" \
                > "$REPORT_DIR/trivy-$(basename $dockerfile).txt" 2>&1 || true
            
            VULNS=$(grep -c "Total:" "$REPORT_DIR/trivy-$(basename $dockerfile).txt" || echo "0")
            log "Found $VULNS vulnerabilities in $dockerfile"
            ((ISSUES_FOUND += VULNS))
            
            # Clean up
            docker rmi "$IMAGE_NAME" > /dev/null 2>&1 || true
        done
    fi
}

# 3. Scan for secrets with Gitleaks
scan_secrets_gitleaks() {
    log "Running Gitleaks secret scan..."
    
    if check_tool gitleaks; then
        gitleaks detect \
            --source . \
            --report-path "$REPORT_DIR/gitleaks-report.json" \
            --report-format json \
            --verbose \
            --no-git 2>&1 | tee "$REPORT_DIR/gitleaks-output.txt" || true
        
        if [ -f "$REPORT_DIR/gitleaks-report.json" ]; then
            SECRETS_FOUND=$(jq length "$REPORT_DIR/gitleaks-report.json" 2>/dev/null || echo "0")
            log "Gitleaks found $SECRETS_FOUND secrets"
            ((ISSUES_FOUND += SECRETS_FOUND))
            
            if [ "$SECRETS_FOUND" -gt 0 ]; then
                error "❌ SECRETS DETECTED! Review $REPORT_DIR/gitleaks-report.json"
            fi
        fi
    fi
}

# 4. Static application security testing with Semgrep
scan_code_semgrep() {
    log "Running Semgrep SAST scan..."
    
    if check_tool semgrep; then
        semgrep \
            --config auto \
            --severity ERROR \
            --severity WARNING \
            --json \
            --output "$REPORT_DIR/semgrep-report.json" \
            . 2>&1 | tee "$REPORT_DIR/semgrep-output.txt" || true
        
        if [ -f "$REPORT_DIR/semgrep-report.json" ]; then
            SEMGREP_ISSUES=$(jq '.results | length' "$REPORT_DIR/semgrep-report.json" 2>/dev/null || echo "0")
            log "Semgrep found $SEMGREP_ISSUES issues"
            ((ISSUES_FOUND += SEMGREP_ISSUES))
        fi
    fi
}

# 5. Scan dependencies
scan_dependencies() {
    log "Scanning dependencies for vulnerabilities..."
    
    # NPM audit (if package.json exists)
    if [ -f "package.json" ] && check_tool npm; then
        npm audit --json > "$REPORT_DIR/npm-audit.json" 2>&1 || true
        
        if [ -f "$REPORT_DIR/npm-audit.json" ]; then
            NPM_VULNS=$(jq '.metadata.vulnerabilities.total' "$REPORT_DIR/npm-audit.json" 2>/dev/null || echo "0")
            log "NPM audit found $NPM_VULNS vulnerabilities"
            ((ISSUES_FOUND += NPM_VULNS))
        fi
    fi
    
    # Python safety check (if requirements.txt exists)
    if [ -f "requirements.txt" ] && check_tool safety; then
        safety check --json > "$REPORT_DIR/safety-report.json" 2>&1 || true
    fi
}

# 6. Kubernetes manifest security with kubesec
scan_k8s_kubesec() {
    log "Scanning Kubernetes manifests with kubesec..."
    
    if check_tool kubesec; then
        find . -name "*.yaml" -o -name "*.yml" | grep -E "(k8s|kubernetes|manifests)" | while read -r manifest; do
            kubesec scan "$manifest" > "$REPORT_DIR/kubesec-$(basename $manifest).json" 2>&1 || true
        done
    fi
}

# Run all scans
scan_iac_checkov
scan_containers_trivy
scan_secrets_gitleaks
scan_code_semgrep
scan_dependencies
scan_k8s_kubesec

# Generate summary report
cat > "$REPORT_FILE" <<EOF
========================================
Security Scan Summary
========================================
Date: $(date)
Total Issues Found: $ISSUES_FOUND

Scan Results:
------------

1. Infrastructure as Code (Checkov)
   Report: $REPORT_DIR/checkov-report.txt

2. Container Vulnerabilities (Trivy)
   Reports: $REPORT_DIR/trivy-*.txt

3. Secret Detection (Gitleaks)
   Report: $REPORT_DIR/gitleaks-report.json

4. SAST Analysis (Semgrep)
   Report: $REPORT_DIR/semgrep-report.json

5. Dependency Vulnerabilities
   NPM: $REPORT_DIR/npm-audit.json

6. Kubernetes Security (kubesec)
   Reports: $REPORT_DIR/kubesec-*.json

Next Steps:
-----------
1. Review all reports in $REPORT_DIR/
2. Prioritize CRITICAL and HIGH severity issues
3. Fix detected vulnerabilities
4. Re-run scan to verify fixes

========================================
EOF

cat "$REPORT_FILE"

# Exit with error if critical issues found
if [ $ISSUES_FOUND -gt 0 ]; then
    error "Security scan completed with $ISSUES_FOUND issues"
    exit 1
else
    log "✓ Security scan completed - No issues found"
    exit 0
fi
