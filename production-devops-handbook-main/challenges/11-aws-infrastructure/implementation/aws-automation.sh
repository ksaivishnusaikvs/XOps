#!/bin/bash

################################################################################
# AWS CLI Automation Scripts Collection
#
# Purpose: Common AWS automation tasks using AWS CLI
# Features:
#   - Multi-region resource deployment
#   - Automated backup and disaster recovery
#   - Security compliance checks
#   - Cost optimization automation
#   - Infrastructure validation
#
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION
# ============================================================================

AWS_REGIONS=("us-east-1" "eu-west-1" "ap-southeast-1")
AWS_PROFILE="${AWS_PROFILE:-default}"
BACKUP_RETENTION_DAYS=35
LOG_FILE="/var/log/aws-automation.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() { log "${BLUE}[INFO]${NC} $*"; }
log_success() { log "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { log "${YELLOW}[WARNING]${NC} $*"; }
log_error() { log "${RED}[ERROR]${NC} $*"; }

# ============================================================================
# MULTI-REGION RDS SNAPSHOT REPLICATION
# ============================================================================

replicate_rds_snapshots() {
    local source_region="$1"
    local target_region="$2"
    local db_instance_id="$3"
    
    log_info "Replicating RDS snapshots from $source_region to $target_region..."
    
    # Get latest automated snapshot
    local latest_snapshot
    latest_snapshot=$(aws rds describe-db-snapshots \
        --region "$source_region" \
        --profile "$AWS_PROFILE" \
        --db-instance-identifier "$db_instance_id" \
        --snapshot-type automated \
        --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
        --output text)
    
    if [[ -z "$latest_snapshot" ]]; then
        log_error "No automated snapshots found for $db_instance_id"
        return 1
    fi
    
    log_info "Latest snapshot: $latest_snapshot"
    
    # Create snapshot copy in target region
    local copy_snapshot_id="${db_instance_id}-cross-region-$(date +%Y%m%d-%H%M%S)"
    
    aws rds copy-db-snapshot \
        --region "$target_region" \
        --profile "$AWS_PROFILE" \
        --source-db-snapshot-identifier "arn:aws:rds:${source_region}:$(aws sts get-caller-identity --query Account --output text):snapshot:${latest_snapshot}" \
        --target-db-snapshot-identifier "$copy_snapshot_id" \
        --kms-key-id "alias/aws/rds" \
        --copy-tags
    
    log_success "Snapshot replication initiated: $copy_snapshot_id in $target_region"
}

# ============================================================================
# AUTOMATED AMI BACKUP
# ============================================================================

create_ami_backups() {
    local tag_filter="$1"
    local region="${2:-us-east-1}"
    
    log_info "Creating AMI backups for instances with tag: $tag_filter in $region..."
    
    # Get instance IDs matching tag
    local instance_ids
    instance_ids=$(aws ec2 describe-instances \
        --region "$region" \
        --profile "$AWS_PROFILE" \
        --filters "Name=tag:$tag_filter,Values=*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
    
    if [[ -z "$instance_ids" ]]; then
        log_warning "No instances found with tag: $tag_filter"
        return 0
    fi
    
    for instance_id in $instance_ids; do
        local ami_name="${instance_id}-backup-$(date +%Y%m%d-%H%M%S)"
        
        log_info "Creating AMI for instance: $instance_id"
        
        local ami_id
        ami_id=$(aws ec2 create-image \
            --region "$region" \
            --profile "$AWS_PROFILE" \
            --instance-id "$instance_id" \
            --name "$ami_name" \
            --description "Automated backup created on $(date)" \
            --no-reboot \
            --tag-specifications "ResourceType=image,Tags=[{Key=AutoBackup,Value=true},{Key=CreatedDate,Value=$(date +%Y-%m-%d)},{Key=SourceInstance,Value=$instance_id}]" \
            --query 'ImageId' \
            --output text)
        
        log_success "AMI created: $ami_id for instance $instance_id"
    done
}

# ============================================================================
# CLEANUP OLD AMIs
# ============================================================================

cleanup_old_amis() {
    local retention_days="${1:-30}"
    local region="${2:-us-east-1}"
    
    log_info "Cleaning up AMIs older than $retention_days days in $region..."
    
    local cutoff_date
    cutoff_date=$(date -d "$retention_days days ago" +%Y-%m-%d)
    
    # Get AMIs with AutoBackup tag older than retention
    local old_amis
    old_amis=$(aws ec2 describe-images \
        --region "$region" \
        --profile "$AWS_PROFILE" \
        --owners self \
        --filters "Name=tag:AutoBackup,Values=true" \
        --query "Images[?CreationDate<='${cutoff_date}'].ImageId" \
        --output text)
    
    if [[ -z "$old_amis" ]]; then
        log_info "No old AMIs to cleanup"
        return 0
    fi
    
    for ami_id in $old_amis; do
        log_info "Deregistering old AMI: $ami_id"
        
        # Get snapshot IDs before deregistering
        local snapshot_ids
        snapshot_ids=$(aws ec2 describe-images \
            --region "$region" \
            --profile "$AWS_PROFILE" \
            --image-ids "$ami_id" \
            --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' \
            --output text)
        
        # Deregister AMI
        aws ec2 deregister-image \
            --region "$region" \
            --profile "$AWS_PROFILE" \
            --image-id "$ami_id"
        
        log_success "Deregistered AMI: $ami_id"
        
        # Delete associated snapshots
        for snapshot_id in $snapshot_ids; do
            if [[ -n "$snapshot_id" ]]; then
                aws ec2 delete-snapshot \
                    --region "$region" \
                    --profile "$AWS_PROFILE" \
                    --snapshot-id "$snapshot_id" || log_warning "Failed to delete snapshot: $snapshot_id"
                
                log_success "Deleted snapshot: $snapshot_id"
            fi
        done
    done
}

# ============================================================================
# S3 CROSS-REGION REPLICATION SETUP
# ============================================================================

setup_s3_replication() {
    local source_bucket="$1"
    local destination_bucket="$2"
    local source_region="$3"
    local destination_region="$4"
    
    log_info "Setting up S3 cross-region replication: $source_bucket → $destination_bucket"
    
    # Enable versioning on both buckets
    aws s3api put-bucket-versioning \
        --bucket "$source_bucket" \
        --profile "$AWS_PROFILE" \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket "$destination_bucket" \
        --profile "$AWS_PROFILE" \
        --versioning-configuration Status=Enabled
    
    log_success "Enabled versioning on both buckets"
    
    # Create replication role (simplified - requires trust policy)
    local role_name="s3-replication-role-${source_bucket}"
    
    # Create replication configuration
    cat > /tmp/replication-config.json <<EOF
{
  "Role": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${role_name}",
  "Rules": [
    {
      "Status": "Enabled",
      "Priority": 1,
      "DeleteMarkerReplication": { "Status": "Enabled" },
      "Filter": {},
      "Destination": {
        "Bucket": "arn:aws:s3:::${destination_bucket}",
        "ReplicationTime": {
          "Status": "Enabled",
          "Time": {
            "Minutes": 15
          }
        },
        "Metrics": {
          "Status": "Enabled",
          "EventThreshold": {
            "Minutes": 15
          }
        }
      }
    }
  ]
}
EOF
    
    aws s3api put-bucket-replication \
        --bucket "$source_bucket" \
        --profile "$AWS_PROFILE" \
        --replication-configuration file:///tmp/replication-config.json
    
    rm /tmp/replication-config.json
    
    log_success "S3 replication configured successfully"
}

# ============================================================================
# ROUTE 53 HEALTH CHECK CREATION
# ============================================================================

create_route53_health_check() {
    local domain="$1"
    local port="${2:-443}"
    local path="${3:-/health}"
    
    log_info "Creating Route 53 health check for $domain:$port$path..."
    
    local health_check_id
    health_check_id=$(aws route53 create-health-check \
        --profile "$AWS_PROFILE" \
        --caller-reference "$(date +%s)" \
        --health-check-config "Type=HTTPS,ResourcePath=${path},FullyQualifiedDomainName=${domain},Port=${port},RequestInterval=30,FailureThreshold=3" \
        --health-check-tags "Key=Name,Value=${domain}-health-check" "Key=AutoCreated,Value=true" \
        --query 'HealthCheck.Id' \
        --output text)
    
    log_success "Health check created: $health_check_id"
    
    # Enable CloudWatch alarm for health check
    aws cloudwatch put-metric-alarm \
        --profile "$AWS_PROFILE" \
        --alarm-name "${domain}-health-check-alarm" \
        --alarm-description "Alert when ${domain} health check fails" \
        --metric-name HealthCheckStatus \
        --namespace AWS/Route53 \
        --statistic Minimum \
        --period 60 \
        --evaluation-periods 2 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --dimensions Name=HealthCheckId,Value="$health_check_id"
    
    log_success "CloudWatch alarm created for health check"
}

# ============================================================================
# LAMBDA FUNCTION DEPLOYMENT
# ============================================================================

deploy_lambda_function() {
    local function_name="$1"
    local zip_file="$2"
    local handler="$3"
    local runtime="${4:-python3.9}"
    local role_arn="$5"
    local region="${6:-us-east-1}"
    
    log_info "Deploying Lambda function: $function_name in $region..."
    
    # Check if function exists
    if aws lambda get-function \
        --region "$region" \
        --profile "$AWS_PROFILE" \
        --function-name "$function_name" &> /dev/null; then
        
        # Update existing function
        log_info "Function exists, updating code..."
        
        aws lambda update-function-code \
            --region "$region" \
            --profile "$AWS_PROFILE" \
            --function-name "$function_name" \
            --zip-file "fileb://${zip_file}"
        
        log_success "Lambda function code updated: $function_name"
    else
        # Create new function
        log_info "Creating new Lambda function..."
        
        aws lambda create-function \
            --region "$region" \
            --profile "$AWS_PROFILE" \
            --function-name "$function_name" \
            --runtime "$runtime" \
            --role "$role_arn" \
            --handler "$handler" \
            --zip-file "fileb://${zip_file}" \
            --timeout 300 \
            --memory-size 512 \
            --environment "Variables={ENVIRONMENT=production}" \
            --tags "Environment=production,ManagedBy=automation"
        
        log_success "Lambda function created: $function_name"
    fi
}

# ============================================================================
# SECURITY GROUP RULE BACKUP
# ============================================================================

backup_security_groups() {
    local region="${1:-us-east-1}"
    local backup_dir="/tmp/sg-backups"
    
    log_info "Backing up security groups in $region..."
    
    mkdir -p "$backup_dir"
    
    local backup_file="${backup_dir}/security-groups-${region}-$(date +%Y%m%d-%H%M%S).json"
    
    aws ec2 describe-security-groups \
        --region "$region" \
        --profile "$AWS_PROFILE" \
        --output json > "$backup_file"
    
    log_success "Security groups backed up to: $backup_file"
}

# ============================================================================
# EC2 INSTANCE SCHEDULER (DEV ENVIRONMENTS)
# ============================================================================

schedule_dev_instances() {
    local action="$1"  # start or stop
    local tag_filter="${2:-Environment:development}"
    
    log_info "Scheduling dev instances: $action (filter: $tag_filter)..."
    
    for region in "${AWS_REGIONS[@]}"; do
        log_info "Processing region: $region"
        
        local instance_ids
        instance_ids=$(aws ec2 describe-instances \
            --region "$region" \
            --profile "$AWS_PROFILE" \
            --filters "Name=tag:$tag_filter,Values=*" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text)
        
        if [[ -z "$instance_ids" ]]; then
            log_info "No instances found in $region"
            continue
        fi
        
        if [[ "$action" == "stop" ]]; then
            aws ec2 stop-instances \
                --region "$region" \
                --profile "$AWS_PROFILE" \
                --instance-ids $instance_ids
            
            log_success "Stopped instances in $region: $instance_ids"
        elif [[ "$action" == "start" ]]; then
            aws ec2 start-instances \
                --region "$region" \
                --profile "$AWS_PROFILE" \
                --instance-ids $instance_ids
            
            log_success "Started instances in $region: $instance_ids"
        fi
    done
}

# ============================================================================
# COST ALLOCATION TAG ENFORCEMENT
# ============================================================================

enforce_cost_tags() {
    local region="${1:-us-east-1}"
    
    log_info "Enforcing cost allocation tags in $region..."
    
    local required_tags=("Environment" "CostCenter" "Owner" "Project")
    local untagged_count=0
    
    # Check EC2 instances
    local instances
    instances=$(aws ec2 describe-instances \
        --region "$region" \
        --profile "$AWS_PROFILE" \
        --query 'Reservations[].Instances[].[InstanceId,Tags]' \
        --output json)
    
    echo "$instances" | jq -c '.[]' | while read -r instance; do
        local instance_id
        instance_id=$(echo "$instance" | jq -r '.[0]')
        
        local tags
        tags=$(echo "$instance" | jq -r '.[1] // [] | from_entries')
        
        local missing_tags=()
        for tag in "${required_tags[@]}"; do
            if ! echo "$tags" | jq -e "has(\"$tag\")" > /dev/null; then
                missing_tags+=("$tag")
            fi
        done
        
        if [[ ${#missing_tags[@]} -gt 0 ]]; then
            log_warning "Instance $instance_id missing tags: ${missing_tags[*]}"
            ((untagged_count++))
        fi
    done
    
    if [[ $untagged_count -eq 0 ]]; then
        log_success "All instances are properly tagged"
    else
        log_warning "$untagged_count instances have missing tags"
    fi
}

# ============================================================================
# GENERATE INFRASTRUCTURE REPORT
# ============================================================================

generate_infrastructure_report() {
    local region="${1:-us-east-1}"
    local output_file="${2:-/tmp/aws-infrastructure-report.txt}"
    
    log_info "Generating infrastructure report for $region..."
    
    {
        echo "========================================"
        echo "AWS Infrastructure Report"
        echo "Region: $region"
        echo "Generated: $(date)"
        echo "========================================"
        echo ""
        
        echo "EC2 Instances:"
        aws ec2 describe-instances \
            --region "$region" \
            --profile "$AWS_PROFILE" \
            --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0]]' \
            --output table
        echo ""
        
        echo "RDS Instances:"
        aws rds describe-db-instances \
            --region "$region" \
            --profile "$AWS_PROFILE" \
            --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,Engine,DBInstanceStatus]' \
            --output table
        echo ""
        
        echo "Load Balancers:"
        aws elbv2 describe-load-balancers \
            --region "$region" \
            --profile "$AWS_PROFILE" \
            --query 'LoadBalancers[].[LoadBalancerName,Type,Scheme,State.Code]' \
            --output table
        echo ""
        
        echo "S3 Buckets:"
        aws s3 ls --profile "$AWS_PROFILE"
        echo ""
        
    } > "$output_file"
    
    log_success "Infrastructure report generated: $output_file"
}

# ============================================================================
# MAIN MENU
# ============================================================================

show_menu() {
    echo -e "\n${BLUE}=== AWS CLI Automation Scripts ===${NC}"
    echo "1.  Replicate RDS Snapshots Cross-Region"
    echo "2.  Create AMI Backups"
    echo "3.  Cleanup Old AMIs"
    echo "4.  Setup S3 Cross-Region Replication"
    echo "5.  Create Route 53 Health Check"
    echo "6.  Deploy Lambda Function"
    echo "7.  Backup Security Groups"
    echo "8.  Schedule Dev Instances (Start/Stop)"
    echo "9.  Enforce Cost Tags"
    echo "10. Generate Infrastructure Report"
    echo "0.  Exit"
    echo -n "Choose an option: "
}

main() {
    log_info "AWS CLI Automation Scripts started"
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                read -p "Source region: " source_region
                read -p "Target region: " target_region
                read -p "DB instance ID: " db_instance
                replicate_rds_snapshots "$source_region" "$target_region" "$db_instance"
                ;;
            2)
                read -p "Tag filter (e.g., Environment:production): " tag
                read -p "Region (default: us-east-1): " region
                create_ami_backups "$tag" "${region:-us-east-1}"
                ;;
            3)
                read -p "Retention days (default: 30): " days
                read -p "Region (default: us-east-1): " region
                cleanup_old_amis "${days:-30}" "${region:-us-east-1}"
                ;;
            4)
                read -p "Source bucket: " source_bucket
                read -p "Destination bucket: " dest_bucket
                read -p "Source region: " source_region
                read -p "Destination region: " dest_region
                setup_s3_replication "$source_bucket" "$dest_bucket" "$source_region" "$dest_region"
                ;;
            5)
                read -p "Domain: " domain
                read -p "Port (default: 443): " port
                read -p "Path (default: /health): " path
                create_route53_health_check "$domain" "${port:-443}" "${path:-/health}"
                ;;
            6)
                read -p "Function name: " function_name
                read -p "ZIP file path: " zip_file
                read -p "Handler: " handler
                read -p "Runtime (default: python3.9): " runtime
                read -p "Role ARN: " role_arn
                deploy_lambda_function "$function_name" "$zip_file" "$handler" "${runtime:-python3.9}" "$role_arn"
                ;;
            7)
                read -p "Region (default: us-east-1): " region
                backup_security_groups "${region:-us-east-1}"
                ;;
            8)
                read -p "Action (start/stop): " action
                read -p "Tag filter (default: Environment:development): " tag
                schedule_dev_instances "$action" "${tag:-Environment:development}"
                ;;
            9)
                read -p "Region (default: us-east-1): " region
                enforce_cost_tags "${region:-us-east-1}"
                ;;
            10)
                read -p "Region (default: us-east-1): " region
                read -p "Output file (default: /tmp/aws-infrastructure-report.txt): " output
                generate_infrastructure_report "${region:-us-east-1}" "${output:-/tmp/aws-infrastructure-report.txt}"
                ;;
            0)
                log_info "Exiting AWS CLI Automation Scripts"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
