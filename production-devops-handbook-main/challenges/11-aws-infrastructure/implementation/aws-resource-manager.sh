#!/bin/bash

################################################################################
# AWS Resource Manager - Production-Ready Bash Script
#
# Purpose: Comprehensive AWS resource management and automation
# Features:
#   - EC2 instance management (start/stop/list)
#   - RDS snapshot creation and restoration
#   - S3 bucket lifecycle management
#   - Security group auditing
#   - Resource tagging enforcement
#   - Cost allocation reporting
#
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/aws-resource-manager.log}"
DRY_RUN="${DRY_RUN:-false}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"

# Required tags for compliance
REQUIRED_TAGS=("Environment" "CostCenter" "Owner" "Project")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

check_dependencies() {
    local deps=("aws" "jq")
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    log_success "All dependencies found"
}

check_aws_credentials() {
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    local account_id
    account_id=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
    log_info "Using AWS Account: $account_id"
}

confirm_action() {
    local message="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would execute: $message"
        return 0
    fi
    
    read -p "$(echo -e "${YELLOW}${message} (y/N):${NC} ")" -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# ============================================================================
# EC2 MANAGEMENT
# ============================================================================

list_ec2_instances() {
    log_info "Listing EC2 instances in $AWS_REGION..."
    
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0],LaunchTime]' \
        --output table
}

start_ec2_instances() {
    local tag_filter="$1"
    
    log_info "Finding instances with tag: $tag_filter"
    
    local instance_ids
    instance_ids=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --filters "Name=tag:$tag_filter,Values=*" "Name=instance-state-name,Values=stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
    
    if [[ -z "$instance_ids" ]]; then
        log_warning "No stopped instances found with tag: $tag_filter"
        return 0
    fi
    
    log_info "Found instances: $instance_ids"
    
    if confirm_action "Start these instances?"; then
        if [[ "$DRY_RUN" != "true" ]]; then
            aws ec2 start-instances \
                --region "$AWS_REGION" \
                --profile "$AWS_PROFILE" \
                --instance-ids $instance_ids
            
            log_success "Started instances: $instance_ids"
        fi
    fi
}

stop_ec2_instances() {
    local tag_filter="$1"
    
    log_info "Finding instances with tag: $tag_filter"
    
    local instance_ids
    instance_ids=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --filters "Name=tag:$tag_filter,Values=*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
    
    if [[ -z "$instance_ids" ]]; then
        log_warning "No running instances found with tag: $tag_filter"
        return 0
    fi
    
    log_info "Found instances: $instance_ids"
    
    if confirm_action "Stop these instances?"; then
        if [[ "$DRY_RUN" != "true" ]]; then
            aws ec2 stop-instances \
                --region "$AWS_REGION" \
                --profile "$AWS_PROFILE" \
                --instance-ids $instance_ids
            
            log_success "Stopped instances: $instance_ids"
        fi
    fi
}

# ============================================================================
# RDS MANAGEMENT
# ============================================================================

create_rds_snapshot() {
    local db_instance="$1"
    local snapshot_id="$2"
    
    log_info "Creating snapshot of RDS instance: $db_instance"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        aws rds create-db-snapshot \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --db-instance-identifier "$db_instance" \
            --db-snapshot-identifier "$snapshot_id" \
            --tags "Key=CreatedBy,Value=aws-resource-manager" "Key=CreatedAt,Value=$(date +%Y-%m-%d)"
        
        log_success "Snapshot created: $snapshot_id"
        
        # Wait for snapshot to complete
        log_info "Waiting for snapshot to complete..."
        aws rds wait db-snapshot-completed \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --db-snapshot-identifier "$snapshot_id"
        
        log_success "Snapshot completed successfully"
    fi
}

list_rds_instances() {
    log_info "Listing RDS instances in $AWS_REGION..."
    
    aws rds describe-db-instances \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,Engine,DBInstanceStatus,MultiAZ,StorageEncrypted]' \
        --output table
}

# ============================================================================
# S3 MANAGEMENT
# ============================================================================

enable_s3_versioning() {
    local bucket_name="$1"
    
    log_info "Enabling versioning on S3 bucket: $bucket_name"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        aws s3api put-bucket-versioning \
            --profile "$AWS_PROFILE" \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled
        
        log_success "Versioning enabled on bucket: $bucket_name"
    fi
}

apply_s3_lifecycle_policy() {
    local bucket_name="$1"
    
    log_info "Applying lifecycle policy to S3 bucket: $bucket_name"
    
    local policy_file="/tmp/s3-lifecycle-policy.json"
    
    cat > "$policy_file" <<'EOF'
{
  "Rules": [
    {
      "Id": "archive-old-objects",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "logs/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        },
        {
          "Days": 365,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ]
    },
    {
      "Id": "delete-old-versions",
      "Status": "Enabled",
      "NoncurrentVersionTransitions": [
        {
          "NoncurrentDays": 30,
          "StorageClass": "STANDARD_IA"
        }
      ],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    }
  ]
}
EOF
    
    if [[ "$DRY_RUN" != "true" ]]; then
        aws s3api put-bucket-lifecycle-configuration \
            --profile "$AWS_PROFILE" \
            --bucket "$bucket_name" \
            --lifecycle-configuration file://"$policy_file"
        
        log_success "Lifecycle policy applied to bucket: $bucket_name"
    fi
    
    rm -f "$policy_file"
}

enable_s3_encryption() {
    local bucket_name="$1"
    
    log_info "Enabling encryption on S3 bucket: $bucket_name"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        aws s3api put-bucket-encryption \
            --profile "$AWS_PROFILE" \
            --bucket "$bucket_name" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }]
            }'
        
        log_success "Encryption enabled on bucket: $bucket_name"
    fi
}

# ============================================================================
# SECURITY GROUP AUDITING
# ============================================================================

audit_security_groups() {
    log_info "Auditing security groups for overly permissive rules..."
    
    local security_groups
    security_groups=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'SecurityGroups[].GroupId' \
        --output text)
    
    local issues_found=0
    
    for sg in $security_groups; do
        local sg_details
        sg_details=$(aws ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --group-ids "$sg" \
            --output json)
        
        local sg_name
        sg_name=$(echo "$sg_details" | jq -r '.SecurityGroups[0].GroupName')
        
        # Check for 0.0.0.0/0 on SSH (port 22)
        local ssh_open
        ssh_open=$(echo "$sg_details" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.FromPort==22) | .IpRanges[] | select(.CidrIp=="0.0.0.0/0") | .CidrIp')
        
        if [[ -n "$ssh_open" ]]; then
            log_error "Security Group $sg ($sg_name) allows SSH from 0.0.0.0/0"
            ((issues_found++))
        fi
        
        # Check for 0.0.0.0/0 on RDP (port 3389)
        local rdp_open
        rdp_open=$(echo "$sg_details" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.FromPort==3389) | .IpRanges[] | select(.CidrIp=="0.0.0.0/0") | .CidrIp')
        
        if [[ -n "$rdp_open" ]]; then
            log_error "Security Group $sg ($sg_name) allows RDP from 0.0.0.0/0"
            ((issues_found++))
        fi
    done
    
    if [[ $issues_found -eq 0 ]]; then
        log_success "No security group issues found"
    else
        log_warning "Found $issues_found security group issues"
    fi
}

# ============================================================================
# RESOURCE TAGGING
# ============================================================================

audit_resource_tags() {
    log_info "Auditing resource tags for compliance..."
    
    local untagged_count=0
    
    # Check EC2 instances
    local instances
    instances=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Reservations[].Instances[].[InstanceId,Tags]' \
        --output json)
    
    echo "$instances" | jq -c '.[]' | while read -r instance; do
        local instance_id
        instance_id=$(echo "$instance" | jq -r '.[0]')
        
        local tags
        tags=$(echo "$instance" | jq -r '.[1] // [] | from_entries')
        
        local missing_tags=()
        for required_tag in "${REQUIRED_TAGS[@]}"; do
            if ! echo "$tags" | jq -e "has(\"$required_tag\")" > /dev/null; then
                missing_tags+=("$required_tag")
            fi
        done
        
        if [[ ${#missing_tags[@]} -gt 0 ]]; then
            log_warning "Instance $instance_id missing tags: ${missing_tags[*]}"
            ((untagged_count++))
        fi
    done
    
    if [[ $untagged_count -eq 0 ]]; then
        log_success "All resources are properly tagged"
    else
        log_warning "$untagged_count resources have missing tags"
    fi
}

# ============================================================================
# COST REPORTING
# ============================================================================

generate_cost_report() {
    local start_date="$1"
    local end_date="$2"
    
    log_info "Generating cost report from $start_date to $end_date..."
    
    # Requires AWS Cost Explorer API
    if ! aws ce get-cost-and-usage \
        --time-period Start="$start_date",End="$end_date" \
        --granularity MONTHLY \
        --metrics "UnblendedCost" \
        --group-by Type=DIMENSION,Key=SERVICE \
        --profile "$AWS_PROFILE" \
        --output table; then
        log_error "Failed to generate cost report. Ensure Cost Explorer is enabled."
    fi
}

# ============================================================================
# MAIN MENU
# ============================================================================

show_menu() {
    echo -e "\n${BLUE}=== AWS Resource Manager ===${NC}"
    echo "1.  List EC2 Instances"
    echo "2.  Start EC2 Instances (by tag)"
    echo "3.  Stop EC2 Instances (by tag)"
    echo "4.  List RDS Instances"
    echo "5.  Create RDS Snapshot"
    echo "6.  Enable S3 Versioning"
    echo "7.  Apply S3 Lifecycle Policy"
    echo "8.  Enable S3 Encryption"
    echo "9.  Audit Security Groups"
    echo "10. Audit Resource Tags"
    echo "11. Generate Cost Report"
    echo "0.  Exit"
    echo -n "Choose an option: "
}

main() {
    log_info "AWS Resource Manager started"
    
    check_dependencies
    check_aws_credentials
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                list_ec2_instances
                ;;
            2)
                read -p "Enter tag filter (e.g., Environment:development): " tag
                start_ec2_instances "$tag"
                ;;
            3)
                read -p "Enter tag filter (e.g., Environment:development): " tag
                stop_ec2_instances "$tag"
                ;;
            4)
                list_rds_instances
                ;;
            5)
                read -p "Enter RDS instance identifier: " db_instance
                read -p "Enter snapshot identifier: " snapshot_id
                create_rds_snapshot "$db_instance" "$snapshot_id"
                ;;
            6)
                read -p "Enter S3 bucket name: " bucket
                enable_s3_versioning "$bucket"
                ;;
            7)
                read -p "Enter S3 bucket name: " bucket
                apply_s3_lifecycle_policy "$bucket"
                ;;
            8)
                read -p "Enter S3 bucket name: " bucket
                enable_s3_encryption "$bucket"
                ;;
            9)
                audit_security_groups
                ;;
            10)
                audit_resource_tags
                ;;
            11)
                read -p "Enter start date (YYYY-MM-DD): " start_date
                read -p "Enter end date (YYYY-MM-DD): " end_date
                generate_cost_report "$start_date" "$end_date"
                ;;
            0)
                log_info "Exiting AWS Resource Manager"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
