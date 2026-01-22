#!/bin/bash
#
# Pre-commit Hooks Setup for Infrastructure as Code
# Installs and configures security scanning for Terraform
#
# Usage: ./pre-commit-setup.sh
#

set -euo pipefail

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

log "Setting up pre-commit hooks for IaC security..."

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not in a git repository. Please run this script from your project root."
    exit 1
fi

# Install pre-commit if not already installed
if ! command -v pre-commit &> /dev/null; then
    log "Installing pre-commit..."
    
    if command -v pip3 &> /dev/null; then
        pip3 install pre-commit
    elif command -v pip &> /dev/null; then
        pip install pre-commit
    elif command -v brew &> /dev/null; then
        brew install pre-commit
    else
        error "Cannot install pre-commit. Please install Python pip first."
        exit 1
    fi
fi

# Install tflint if not already installed
if ! command -v tflint &> /dev/null; then
    log "Installing tflint..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install tflint
    else
        curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
    fi
fi

# Install terraform-docs if not already installed
if ! command -v terraform-docs &> /dev/null; then
    log "Installing terraform-docs..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install terraform-docs
    else
        curl -Lo ./terraform-docs.tar.gz https://github.com/terraform-docs/terraform-docs/releases/download/v0.16.0/terraform-docs-v0.16.0-linux-amd64.tar.gz
        tar -xzf terraform-docs.tar.gz
        chmod +x terraform-docs
        sudo mv terraform-docs /usr/local/bin/
        rm terraform-docs.tar.gz
    fi
fi

# Install checkov if not already installed
if ! command -v checkov &> /dev/null; then
    log "Installing checkov..."
    pip3 install checkov
fi

# Create .pre-commit-config.yaml
log "Creating .pre-commit-config.yaml..."

cat > .pre-commit-config.yaml <<'EOF'
# Pre-commit hooks for Infrastructure as Code
# See https://pre-commit.com for more information

repos:
  # Terraform formatting and validation
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.83.5
    hooks:
      - id: terraform_fmt
        name: Terraform format
        description: Rewrites Terraform files to canonical format
        
      - id: terraform_validate
        name: Terraform validate
        description: Validates Terraform configuration files
        
      - id: terraform_docs
        name: Terraform docs
        description: Generates documentation from Terraform modules
        args:
          - --args=--config=.terraform-docs.yml
          
      - id: terraform_tflint
        name: Terraform lint
        description: Lints Terraform files with tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
          
      - id: terraform_checkov
        name: Checkov security scan
        description: Runs Checkov security scanner on Terraform
        args:
          - --args=--quiet
          - --args=--framework terraform
          
      - id: terraform_tfsec
        name: TFSec security scan
        description: Runs tfsec security scanner
        args:
          - --args=--minimum-severity=MEDIUM

  # General file checks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
        name: Trim trailing whitespace
        
      - id: end-of-file-fixer
        name: Fix end of files
        
      - id: check-yaml
        name: Check YAML syntax
        args: ['--allow-multiple-documents']
        
      - id: check-json
        name: Check JSON syntax
        
      - id: check-merge-conflict
        name: Check for merge conflicts
        
      - id: detect-private-key
        name: Detect private keys
        
      - id: check-added-large-files
        name: Check for large files
        args: ['--maxkb=1000']

  # Secret scanning
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        name: Detect secrets
        args: ['--baseline', '.secrets.baseline']
        exclude: package-lock.json

  # Markdown linting
  - repo: https://github.com/markdownlint/markdownlint
    rev: v0.12.0
    hooks:
      - id: markdownlint
        name: Markdown lint
        args: ['-r', '~MD013,~MD033']
EOF

log ".pre-commit-config.yaml created"

# Create .tflint.hcl configuration
log "Creating .tflint.hcl configuration..."

cat > .tflint.hcl <<'EOF'
# TFLint configuration for Terraform best practices

config {
  module = true
  force = false
}

plugin "aws" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "azurerm" {
  enabled = false
  version = "0.25.1"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Naming conventions
rule "terraform_naming_convention" {
  enabled = true
}

# Required version
rule "terraform_required_version" {
  enabled = true
}

# Required providers
rule "terraform_required_providers" {
  enabled = true
}

# Deprecated syntax
rule "terraform_deprecated_index" {
  enabled = true
}

# Type constraints
rule "terraform_typed_variables" {
  enabled = true
}

# Unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# Documentation
rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}
EOF

log ".tflint.hcl created"

# Create .terraform-docs.yml configuration
log "Creating .terraform-docs.yml configuration..."

cat > .terraform-docs.yml <<'EOF'
# Terraform Docs configuration

formatter: markdown table

version: ""

header-from: main.tf
footer-from: ""

recursive:
  enabled: false
  path: modules

sections:
  hide: []
  show: []

content: |-
  {{ .Header }}
  
  ## Requirements
  
  {{ .Requirements }}
  
  ## Providers
  
  {{ .Providers }}
  
  ## Modules
  
  {{ .Modules }}
  
  ## Resources
  
  {{ .Resources }}
  
  ## Inputs
  
  {{ .Inputs }}
  
  ## Outputs
  
  {{ .Outputs }}

output:
  file: README.md
  mode: inject
  template: |-
    <!-- BEGIN_TF_DOCS -->
    {{ .Content }}
    <!-- END_TF_DOCS -->

sort:
  enabled: true
  by: name

settings:
  anchor: true
  color: true
  default: true
  description: true
  escape: true
  hide-empty: false
  html: true
  indent: 2
  lockfile: true
  read-comments: true
  required: true
  sensitive: true
  type: true
EOF

log ".terraform-docs.yml created"

# Initialize secrets baseline
log "Initializing secrets baseline..."
if command -v detect-secrets &> /dev/null; then
    detect-secrets scan > .secrets.baseline 2>/dev/null || true
    log ".secrets.baseline created"
else
    warning "detect-secrets not installed, skipping baseline creation"
fi

# Install pre-commit hooks
log "Installing pre-commit hooks..."
pre-commit install
pre-commit install --hook-type commit-msg

# Create .gitignore additions
log "Adding Terraform files to .gitignore..."

cat >> .gitignore <<'EOF'

# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
crash.log
crash.*.log
*.tfvars
*.tfvars.json
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
.terraform.lock.hcl

# Pre-commit
.pre-commit-config.yaml.backup
EOF

log ".gitignore updated"

# Create a sample Terraform file to test hooks
log "Creating sample test file..."

cat > test.tf <<'EOF'
# Sample Terraform file for testing pre-commit hooks

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

resource "aws_s3_bucket" "example" {
  bucket = "my-test-bucket-${var.environment}"
  
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
EOF

log "test.tf created"

# Run pre-commit on all files
log "Running pre-commit on all files (this may take a moment)..."
pre-commit run --all-files || warning "Some checks failed - this is expected for the first run"

# Create documentation
cat > PRE_COMMIT_GUIDE.md <<'EOF'
# Pre-commit Hooks Guide

This project uses pre-commit hooks to ensure code quality and security.

## Installed Hooks

### Terraform Hooks
- **terraform_fmt**: Automatically formats Terraform files
- **terraform_validate**: Validates Terraform syntax
- **terraform_docs**: Auto-generates documentation
- **terraform_tflint**: Lints Terraform code for best practices
- **terraform_checkov**: Security scanning with Checkov
- **terraform_tfsec**: Security scanning with TFSec

### General Hooks
- **trailing-whitespace**: Removes trailing whitespace
- **end-of-file-fixer**: Ensures files end with newline
- **check-yaml**: Validates YAML syntax
- **check-json**: Validates JSON syntax
- **check-merge-conflict**: Detects merge conflict markers
- **detect-private-key**: Prevents committing private keys
- **check-added-large-files**: Prevents large files (>1MB)

### Secret Detection
- **detect-secrets**: Scans for hardcoded secrets

## Usage

### Automatic (on commit)
Hooks run automatically when you commit:
```bash
git add .
git commit -m "Your message"
# Hooks run automatically
```

### Manual
Run all hooks manually:
```bash
pre-commit run --all-files
```

Run specific hook:
```bash
pre-commit run terraform_fmt
pre-commit run checkov
```

### Skip hooks (emergency only)
```bash
git commit --no-verify -m "Emergency fix"
```

## Troubleshooting

### Hook fails on terraform_validate
Make sure you've run `terraform init` first:
```bash
terraform init
```

### Checkov takes too long
Skip checkov for quick commits:
```bash
SKIP=terraform_checkov git commit -m "Quick fix"
```

### Update hooks
```bash
pre-commit autoupdate
```

## Configuration Files

- `.pre-commit-config.yaml`: Pre-commit hook configuration
- `.tflint.hcl`: TFLint rules and settings
- `.terraform-docs.yml`: Documentation generation settings
- `.secrets.baseline`: Baseline for secret detection

## Best Practices

1. Run hooks before creating PR
2. Don't skip hooks unless absolutely necessary
3. Fix all security findings before merge
4. Keep hooks updated regularly
5. Add custom rules as project grows
EOF

log "PRE_COMMIT_GUIDE.md created"

# Summary
cat <<EOF

========================================
Pre-commit Hooks Setup Complete!
========================================

Installed Tools:
✓ pre-commit
✓ tflint
✓ terraform-docs
✓ checkov

Configuration Files:
✓ .pre-commit-config.yaml (Hook configuration)
✓ .tflint.hcl (Linting rules)
✓ .terraform-docs.yml (Documentation settings)
✓ .secrets.baseline (Secret detection baseline)
✓ PRE_COMMIT_GUIDE.md (Usage guide)

Hooks are now active!

Next time you commit, the following checks will run:
- Terraform formatting
- Terraform validation
- Security scanning (Checkov, TFSec)
- Linting (TFLint)
- Secret detection
- Documentation generation

Test it now:
  git add test.tf
  git commit -m "Test pre-commit hooks"

For more info, see: PRE_COMMIT_GUIDE.md

========================================
EOF

log "Setup complete!"
