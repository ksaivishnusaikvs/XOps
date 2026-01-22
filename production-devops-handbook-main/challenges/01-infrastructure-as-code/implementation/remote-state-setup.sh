#!/bin/bash
#
# Remote State Backend Setup Script
# Sets up S3 + DynamoDB for Terraform state management with encryption
#
# Usage: ./remote-state-setup.sh <environment> <region>
# Example: ./remote-state-setup.sh production us-east-1
#

set -euo pipefail

# Configuration
ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-us-east-1}
PROJECT_NAME="myapp"
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${ENVIRONMENT}"
DYNAMODB_TABLE="${PROJECT_NAME}-terraform-locks-${ENVIRONMENT}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

log "Setting up Terraform remote state backend for environment: $ENVIRONMENT"
log "Region: $AWS_REGION"

# Create S3 bucket for state storage
log "Creating S3 bucket: $BUCKET_NAME"

if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" 2>/dev/null || \
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region us-east-1 2>/dev/null
    
    log "S3 bucket created successfully"
else
    warning "S3 bucket already exists"
fi

# Enable versioning
log "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

# Enable encryption
log "Enabling server-side encryption..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": true
        }]
    }'

# Block public access
log "Blocking public access..."
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable bucket logging
log "Enabling access logging..."
LOGGING_BUCKET="${PROJECT_NAME}-terraform-logs-${ENVIRONMENT}"

# Create logging bucket if it doesn't exist
if aws s3 ls "s3://${LOGGING_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3api create-bucket \
        --bucket "$LOGGING_BUCKET" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" 2>/dev/null || \
    aws s3api create-bucket \
        --bucket "$LOGGING_BUCKET" \
        --region us-east-1 2>/dev/null
fi

aws s3api put-bucket-logging \
    --bucket "$BUCKET_NAME" \
    --bucket-logging-status '{
        "LoggingEnabled": {
            "TargetBucket": "'"$LOGGING_BUCKET"'",
            "TargetPrefix": "state-access-logs/"
        }
    }'

# Add lifecycle policy
log "Adding lifecycle policy..."
aws s3api put-bucket-lifecycle-configuration \
    --bucket "$BUCKET_NAME" \
    --lifecycle-configuration '{
        "Rules": [{
            "Id": "DeleteOldVersions",
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 90
            }
        }]
    }'

# Create DynamoDB table for state locking
log "Creating DynamoDB table: $DYNAMODB_TABLE"

if ! aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &> /dev/null; then
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=ManagedBy,Value=Terraform
    
    log "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION"
    log "DynamoDB table created successfully"
else
    warning "DynamoDB table already exists"
fi

# Enable Point-in-Time Recovery
log "Enabling Point-in-Time Recovery for DynamoDB..."
aws dynamodb update-continuous-backups \
    --table-name "$DYNAMODB_TABLE" \
    --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
    --region "$AWS_REGION"

# Generate Terraform backend configuration
log "Generating Terraform backend configuration..."

cat > backend-${ENVIRONMENT}.tf <<EOF
# Terraform Backend Configuration - Auto-generated
# Environment: ${ENVIRONMENT}
# Generated: $(date)

terraform {
  backend "s3" {
    bucket         = "${BUCKET_NAME}"
    key            = "terraform.tfstate"
    region         = "${AWS_REGION}"
    encrypt        = true
    dynamodb_table = "${DYNAMODB_TABLE}"
    
    # Optional: Enable state locking timeout
    # lock_timeout = "5m"
  }
}
EOF

log "Backend configuration saved to: backend-${ENVIRONMENT}.tf"

# Generate backend initialization script
cat > init-backend-${ENVIRONMENT}.sh <<'EOF'
#!/bin/bash
# Initialize Terraform with remote backend

set -euo pipefail

echo "Initializing Terraform with remote backend..."

# Initialize with backend configuration
terraform init \
    -backend-config="bucket=${BUCKET_NAME}" \
    -backend-config="key=terraform.tfstate" \
    -backend-config="region=${AWS_REGION}" \
    -backend-config="encrypt=true" \
    -backend-config="dynamodb_table=${DYNAMODB_TABLE}"

echo "Terraform backend initialized successfully!"
echo ""
echo "State is now stored in: s3://${BUCKET_NAME}/terraform.tfstate"
echo "State locking table: ${DYNAMODB_TABLE}"
EOF

chmod +x init-backend-${ENVIRONMENT}.sh

# Create IAM policy for Terraform state access
log "Generating IAM policy for Terraform state access..."

cat > terraform-state-policy-${ENVIRONMENT}.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:*:table/${DYNAMODB_TABLE}"
    }
  ]
}
EOF

log "IAM policy saved to: terraform-state-policy-${ENVIRONMENT}.json"

# Summary
cat <<EOF

========================================
Remote State Backend Setup Complete!
========================================

Environment: ${ENVIRONMENT}
Region: ${AWS_REGION}

Resources Created:
✓ S3 Bucket: ${BUCKET_NAME}
  - Versioning: Enabled
  - Encryption: AES256
  - Public Access: Blocked
  - Logging: Enabled

✓ DynamoDB Table: ${DYNAMODB_TABLE}
  - Billing Mode: Pay-per-request
  - Point-in-Time Recovery: Enabled

Files Generated:
- backend-${ENVIRONMENT}.tf (Terraform backend config)
- init-backend-${ENVIRONMENT}.sh (Initialization script)
- terraform-state-policy-${ENVIRONMENT}.json (IAM policy)

Next Steps:
1. Copy backend-${ENVIRONMENT}.tf to your Terraform directory
2. Create IAM policy: 
   aws iam create-policy --policy-name TerraformState${ENVIRONMENT^} \\
       --policy-document file://terraform-state-policy-${ENVIRONMENT}.json
3. Attach policy to your Terraform execution role/user
4. Run: ./init-backend-${ENVIRONMENT}.sh

========================================
EOF

log "Setup complete!"
