# Infrastructure as Code - Step-by-Step Implementation Guide

## Step 1: Set Up Terraform Backend

### 1.1 Create S3 Bucket for State
```bash
aws s3api create-bucket \
  --bucket my-terraform-state-$(aws sts get-caller-identity --query Account --output text) \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket my-terraform-state-$(aws sts get-caller-identity --query Account --output text) \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket my-terraform-state-$(aws sts get-caller-identity --query Account --output text) \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### 1.2 Create DynamoDB Table for State Locking
```bash
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Step 2: Initialize Terraform Project

### 2.1 Create Directory Structure
```bash
mkdir -p terraform/{modules,environments/{dev,staging,prod}}
cd terraform
```

### 2.2 Initialize Terraform
```bash
terraform init
```

### 2.3 Validate Configuration
```bash
terraform validate
terraform fmt -recursive
```

## Step 3: Implement Pre-commit Hooks

### 3.1 Install pre-commit
```bash
pip install pre-commit
```

### 3.2 Create .pre-commit-config.yaml
```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.83.5
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
      - id: terraform_docs
      - id: terraform_checkov
```

### 3.3 Install hooks
```bash
pre-commit install
```

## Step 4: Run Security Scanning

### 4.1 Install Checkov
```bash
pip install checkov
```

### 4.2 Scan Infrastructure Code
```bash
checkov -d . --framework terraform
```

### 4.3 Install tfsec
```bash
# macOS
brew install tfsec

# Linux
curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

# Windows
choco install tfsec
```

### 4.4 Run tfsec
```bash
tfsec .
```

## Step 5: Plan and Apply Changes

### 5.1 Create Workspace for Environment
```bash
terraform workspace new dev
terraform workspace select dev
```

### 5.2 Plan Changes
```bash
terraform plan -out=tfplan
```

### 5.3 Review Plan
```bash
terraform show tfplan
```

### 5.4 Apply Changes
```bash
terraform apply tfplan
```

## Step 6: Implement CI/CD Pipeline

### 6.1 GitHub Actions Example (.github/workflows/terraform.yml)
```yaml
name: Terraform CI/CD

on:
  pull_request:
    paths:
      - 'terraform/**'
  push:
    branches:
      - main
    paths:
      - 'terraform/**'

env:
  TF_VERSION: 1.6.0

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Terraform Format Check
        run: terraform fmt -check -recursive
      
      - name: Terraform Init
        run: terraform init
        
      - name: Terraform Validate
        run: terraform validate
        
      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: terraform/
          framework: terraform
          
      - name: Terraform Plan
        if: github.event_name == 'pull_request'
        run: terraform plan -no-color
        
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve
```

## Step 7: Implement State Management Best Practices

### 7.1 Enable State Encryption
Already configured in backend configuration

### 7.2 Implement State File Backup
```bash
# Add lifecycle policy to S3 bucket
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-terraform-state-$(aws sts get-caller-identity --query Account --output text) \
  --lifecycle-configuration file://lifecycle.json
```

### 7.3 Use Import for Existing Resources
```bash
terraform import aws_instance.example i-1234567890abcdef0
```

## Step 8: Documentation and Maintenance

### 8.1 Generate Documentation
```bash
terraform-docs markdown table . > README.md
```

### 8.2 Regular Updates
```bash
# Check for provider updates
terraform init -upgrade

# Review changes
terraform plan
```

## Step 9: Disaster Recovery

### 9.1 Export State
```bash
terraform state pull > terraform.tfstate.backup
```

### 9.2 Test Destroy and Recreate
```bash
# In non-prod environment
terraform plan -destroy
# Review carefully before applying
```

## Common Commands Reference

```bash
# Initialize
terraform init

# Format code
terraform fmt -recursive

# Validate
terraform validate

# Plan
terraform plan

# Apply
terraform apply

# Destroy
terraform destroy

# Show state
terraform state list
terraform state show <resource>

# Refresh state
terraform refresh

# Import existing resource
terraform import <resource_type>.<name> <id>
```
