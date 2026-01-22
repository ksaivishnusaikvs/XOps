#!/bin/bash
#
# Terraform Drift Detection Script
# Detects configuration drift and alerts when infrastructure diverges from IaC
#
# Usage: ./drift-detection.sh [options]
# Options:
#   -e, --environment   Environment to check (dev/staging/prod)
#   -a, --auto-fix      Automatically fix drift (dangerous!)
#   -n, --notify        Send notification on drift detection
#

set -euo pipefail

# Configuration
ENVIRONMENT="${ENVIRONMENT:-dev}"
AUTO_FIX=false
NOTIFY=false
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
EMAIL="${DRIFT_ALERT_EMAIL:-devops@example.com}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -a|--auto-fix)
            AUTO_FIX=true
            shift
            ;;
        -n|--notify)
            NOTIFY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    error "Terraform is not installed"
    exit 1
fi

# Create reports directory
REPORTS_DIR="drift-reports"
mkdir -p "$REPORTS_DIR"

REPORT_FILE="$REPORTS_DIR/drift-report-$(date +%Y%m%d-%H%M%S).txt"

log "Starting drift detection for environment: $ENVIRONMENT"
log "Report will be saved to: $REPORT_FILE"

# Initialize Terraform
log "Initializing Terraform..."
terraform init -input=false > /dev/null

# Run terraform plan to detect drift
log "Running terraform plan to detect drift..."

if terraform plan -detailed-exitcode -no-color -out=tfplan > "$REPORT_FILE" 2>&1; then
    DRIFT_STATUS="no-drift"
    EXIT_CODE=0
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 2 ]; then
        DRIFT_STATUS="drift-detected"
    else
        DRIFT_STATUS="error"
    fi
fi

# Analyze the drift
if [ "$DRIFT_STATUS" == "no-drift" ]; then
    info "✓ No configuration drift detected!"
    info "Infrastructure matches the Terraform state."
    
    echo "========================================" >> "$REPORT_FILE"
    echo "Drift Detection Report" >> "$REPORT_FILE"
    echo "Environment: $ENVIRONMENT" >> "$REPORT_FILE"
    echo "Date: $(date)" >> "$REPORT_FILE"
    echo "Status: NO DRIFT DETECTED" >> "$REPORT_FILE"
    echo "========================================" >> "$REPORT_FILE"
    
elif [ "$DRIFT_STATUS" == "drift-detected" ]; then
    warning "⚠ Configuration drift detected!"
    warning "Changes found between infrastructure and Terraform state."
    
    # Get detailed changes
    log "Analyzing changes..."
    
    terraform show tfplan > "$REPORTS_DIR/drift-changes-$(date +%Y%m%d-%H%M%S).txt"
    
    # Count changes
    RESOURCES_TO_ADD=$(grep -c "will be created" "$REPORT_FILE" || true)
    RESOURCES_TO_CHANGE=$(grep -c "will be updated" "$REPORT_FILE" || true)
    RESOURCES_TO_DESTROY=$(grep -c "will be destroyed" "$REPORT_FILE" || true)
    
    # Summary
    cat > "$REPORTS_DIR/drift-summary.txt" <<EOF
Configuration Drift Summary
============================
Environment: $ENVIRONMENT
Timestamp: $(date)

Changes Detected:
- Resources to Add: $RESOURCES_TO_ADD
- Resources to Change: $RESOURCES_TO_CHANGE
- Resources to Destroy: $RESOURCES_TO_DESTROY

Total Changes: $((RESOURCES_TO_ADD + RESOURCES_TO_CHANGE + RESOURCES_TO_DESTROY))

Affected Resources:
EOF
    
    # Extract affected resources
    grep -E "# .* will be (created|updated|destroyed)" "$REPORT_FILE" >> "$REPORTS_DIR/drift-summary.txt" || true
    
    cat "$REPORTS_DIR/drift-summary.txt"
    
    # Send notifications
    if [ "$NOTIFY" == "true" ]; then
        send_notifications
    fi
    
    # Auto-fix if enabled
    if [ "$AUTO_FIX" == "true" ]; then
        warning "Auto-fix is enabled. Applying changes..."
        
        if terraform apply -auto-approve tfplan; then
            log "✓ Drift automatically fixed!"
        else
            error "Failed to apply changes automatically"
            exit 1
        fi
    else
        info "To fix the drift, run: terraform apply"
    fi
    
else
    error "Error occurred during drift detection"
    cat "$REPORT_FILE"
    exit 1
fi

# Clean up plan file
rm -f tfplan

# Send notifications function
send_notifications() {
    log "Sending notifications..."
    
    # Slack notification
    if [ -n "$SLACK_WEBHOOK" ]; then
        DRIFT_COUNT=$((RESOURCES_TO_ADD + RESOURCES_TO_CHANGE + RESOURCES_TO_DESTROY))
        
        curl -X POST "$SLACK_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{
                \"text\": \"🚨 Terraform Drift Detected\",
                \"attachments\": [{
                    \"color\": \"warning\",
                    \"fields\": [
                        {\"title\": \"Environment\", \"value\": \"$ENVIRONMENT\", \"short\": true},
                        {\"title\": \"Changes\", \"value\": \"$DRIFT_COUNT\", \"short\": true},
                        {\"title\": \"To Add\", \"value\": \"$RESOURCES_TO_ADD\", \"short\": true},
                        {\"title\": \"To Change\", \"value\": \"$RESOURCES_TO_CHANGE\", \"short\": true},
                        {\"title\": \"To Destroy\", \"value\": \"$RESOURCES_TO_DESTROY\", \"short\": true}
                    ]
                }]
            }" > /dev/null 2>&1
        
        log "Slack notification sent"
    fi
    
    # Email notification
    if command -v mail &> /dev/null; then
        mail -s "Terraform Drift Detected: $ENVIRONMENT" "$EMAIL" < "$REPORTS_DIR/drift-summary.txt"
        log "Email notification sent to $EMAIL"
    fi
}

# Generate HTML report (optional)
generate_html_report() {
    HTML_REPORT="$REPORTS_DIR/drift-report-$(date +%Y%m%d-%H%M%S).html"
    
    cat > "$HTML_REPORT" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Terraform Drift Report - $ENVIRONMENT</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .no-drift { background-color: #d4edda; color: #155724; }
        .drift { background-color: #fff3cd; color: #856404; }
        .error { background-color: #f8d7da; color: #721c24; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        pre { background-color: #f5f5f5; padding: 10px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>Terraform Drift Detection Report</h1>
    <p><strong>Environment:</strong> $ENVIRONMENT</p>
    <p><strong>Date:</strong> $(date)</p>
    
    <div class="status $DRIFT_STATUS">
        <h2>Status: $(echo $DRIFT_STATUS | tr '[:lower:]' '[:upper:]')</h2>
    </div>
    
    <h2>Summary</h2>
    <table>
        <tr><th>Metric</th><th>Count</th></tr>
        <tr><td>Resources to Add</td><td>$RESOURCES_TO_ADD</td></tr>
        <tr><td>Resources to Change</td><td>$RESOURCES_TO_CHANGE</td></tr>
        <tr><td>Resources to Destroy</td><td>$RESOURCES_TO_DESTROY</td></tr>
    </table>
    
    <h2>Details</h2>
    <pre>$(cat "$REPORT_FILE")</pre>
</body>
</html>
EOF
    
    log "HTML report generated: $HTML_REPORT"
}

# Create a cron job template
create_cron_template() {
    cat > "$REPORTS_DIR/cron-template.sh" <<'CRONEOF'
#!/bin/bash
# Cron job for automated drift detection
# Add to crontab: 0 */6 * * * /path/to/drift-detection.sh -e production -n

cd /path/to/terraform/directory
./drift-detection.sh -e production -n
CRONEOF
    
    chmod +x "$REPORTS_DIR/cron-template.sh"
    log "Cron template created: $REPORTS_DIR/cron-template.sh"
}

log "Drift detection complete!"
log "Report saved to: $REPORT_FILE"

exit 0
