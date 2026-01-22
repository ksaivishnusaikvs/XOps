# Terraform Best Practices Implementation

# 1. Use remote state with locking
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
  
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 2. Use variables with validation
variable "environment" {
  description = "Environment name"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "instance_count" {
  description = "Number of instances to create"
  type        = number
  default     = 1
  
  validation {
    condition     = var.instance_count > 0 && var.instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}

# 3. Use locals for computed values
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "MyApp"
    CostCenter  = "Engineering"
  }
  
  name_prefix = "${var.environment}-myapp"
}

# 4. Use data sources for existing resources
data "aws_vpc" "main" {
  tags = {
    Name = "${var.environment}-vpc"
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# 5. Use modules for reusability
module "ec2_instances" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"
  
  count = var.instance_count
  
  name = "${local.name_prefix}-instance-${count.index}"
  
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.instance.id]
  subnet_id              = data.aws_vpc.main.id
  
  tags = local.common_tags
}

# 6. Use security groups with least privilege
resource "aws_security_group" "instance" {
  name_prefix = "${local.name_prefix}-sg-"
  description = "Security group for ${local.name_prefix} instances"
  vpc_id      = data.aws_vpc.main.id
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-sg"
    }
  )
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "https_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = aws_security_group.instance.id
  description       = "Allow HTTPS from internal network"
}

# 7. Use outputs for important values
output "instance_ids" {
  description = "IDs of created EC2 instances"
  value       = module.ec2_instances[*].id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.instance.id
}
