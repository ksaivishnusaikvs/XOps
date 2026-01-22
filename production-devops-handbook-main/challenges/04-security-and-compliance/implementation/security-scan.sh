#!/bin/bash
# Security Scanning and Compliance Automation Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Security Compliance Scan...${NC}\n"

# Configuration
REPORT_DIR="./security-reports"
mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 1. Container Image Scanning with Trivy
echo -e "\n${YELLOW}=== Running Container Security Scan ===${NC}"
if command_exists trivy; then
    trivy image \
        --severity HIGH,CRITICAL \
        --format json \
        --output "$REPORT_DIR/trivy_scan_$TIMESTAMP.json" \
        myapp:latest
    
    trivy image \
        --severity HIGH,CRITICAL \
        --format table \
        myapp:latest | tee "$REPORT_DIR/trivy_scan_$TIMESTAMP.txt"
else
    echo -e "${RED}Trivy not installed. Skipping...${NC}"
fi

# 2. Dependency Scanning
echo -e "\n${YELLOW}=== Running Dependency Security Scan ===${NC}"
if [ -f "package.json" ]; then
    npm audit --json > "$REPORT_DIR/npm_audit_$TIMESTAMP.json"
    npm audit --audit-level=moderate
fi

if [ -f "requirements.txt" ]; then
    if command_exists safety; then
        safety check --json > "$REPORT_DIR/safety_scan_$TIMESTAMP.json"
    fi
fi

if [ -f "Gemfile" ]; then
    bundle audit --update
fi

# 3. Secret Scanning with TruffleHog
echo -e "\n${YELLOW}=== Scanning for Secrets ===${NC}"
if command_exists trufflehog; then
    trufflehog filesystem . \
        --json \
        --exclude-paths .trufflehog-exclude \
        > "$REPORT_DIR/trufflehog_$TIMESTAMP.json"
else
    echo -e "${RED}TruffleHog not installed. Skipping...${NC}"
fi

# 4. Infrastructure as Code Security with Checkov
echo -e "\n${YELLOW}=== Scanning IaC for Security Issues ===${NC}"
if command_exists checkov; then
    checkov -d . \
        --framework terraform kubernetes dockerfile \
        --output json \
        --output-file "$REPORT_DIR/checkov_$TIMESTAMP.json"
    
    checkov -d . \
        --framework terraform kubernetes dockerfile \
        --compact \
        --quiet
else
    echo -e "${RED}Checkov not installed. Skipping...${NC}"
fi

# 5. Kubernetes Security with kube-bench
echo -e "\n${YELLOW}=== Running Kubernetes CIS Benchmark ===${NC}"
if command_exists kube-bench; then
    kube-bench run \
        --json \
        --outputfile "$REPORT_DIR/kube_bench_$TIMESTAMP.json"
else
    echo -e "${RED}kube-bench not installed. Skipping...${NC}"
fi

# 6. SAST with Semgrep
echo -e "\n${YELLOW}=== Running Static Application Security Testing ===${NC}"
if command_exists semgrep; then
    semgrep --config=auto \
        --json \
        --output="$REPORT_DIR/semgrep_$TIMESTAMP.json" \
        .
    
    semgrep --config=auto .
else
    echo -e "${RED}Semgrep not installed. Skipping...${NC}"
fi

# 7. Check for Compliance (RBAC, Network Policies, etc.)
echo -e "\n${YELLOW}=== Checking Kubernetes Compliance ===${NC}"
if command_exists kubectl; then
    echo "Checking for Network Policies..."
    kubectl get networkpolicies --all-namespaces -o json > "$REPORT_DIR/network_policies_$TIMESTAMP.json"
    
    echo "Checking Pod Security Standards..."
    kubectl get pods --all-namespaces -o json > "$REPORT_DIR/pods_security_$TIMESTAMP.json"
    
    echo "Checking RBAC configurations..."
    kubectl get clusterroles,clusterrolebindings,roles,rolebindings --all-namespaces -o json > "$REPORT_DIR/rbac_$TIMESTAMP.json"
fi

# 8. Generate Summary Report
echo -e "\n${YELLOW}=== Generating Summary Report ===${NC}"
cat > "$REPORT_DIR/summary_$TIMESTAMP.md" <<EOF
# Security Compliance Report
**Generated:** $(date)

## Scans Performed
- Container Image Scanning (Trivy)
- Dependency Vulnerability Scanning
- Secret Detection (TruffleHog)
- Infrastructure as Code Security (Checkov)
- Kubernetes CIS Benchmark (kube-bench)
- Static Application Security Testing (Semgrep)
- Kubernetes Compliance Checks

## Reports Location
All detailed reports are available in: $REPORT_DIR

## Next Steps
1. Review all HIGH and CRITICAL findings
2. Create tickets for remediation
3. Update security baseline
4. Schedule next scan

EOF

# 9. Check for critical vulnerabilities and fail if found
echo -e "\n${YELLOW}=== Checking for Critical Issues ===${NC}"
CRITICAL_COUNT=0

if [ -f "$REPORT_DIR/trivy_scan_$TIMESTAMP.json" ]; then
    CRITICAL_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$REPORT_DIR/trivy_scan_$TIMESTAMP.json" || echo "0")
fi

if [ "$CRITICAL_COUNT" -gt 0 ]; then
    echo -e "${RED}CRITICAL: Found $CRITICAL_COUNT critical vulnerabilities!${NC}"
    echo -e "${RED}Please review and remediate before deployment.${NC}"
    exit 1
else
    echo -e "${GREEN}No critical vulnerabilities found.${NC}"
fi

echo -e "\n${GREEN}Security compliance scan complete!${NC}"
echo -e "Reports saved to: $REPORT_DIR"
