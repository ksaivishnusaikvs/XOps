# Multi-Region VPC Infrastructure with Terraform
# This configuration creates a production-ready VPC architecture across 3 AWS regions
# with proper CIDR allocation, subnetting, and security controls

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "terraform-state-prod"
    key            = "multi-region-vpc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    kms_key_id     = "arn:aws:kms:us-east-1:ACCOUNT_ID:key/KEY_ID"
  }
}

# ============================================================================
# VARIABLES
# ============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "multiregion-app"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "regions" {
  description = "AWS regions for multi-region deployment"
  type        = map(object({
    cidr_block = string
    azs        = list(string)
  }))
  default = {
    "us-east-1" = {
      cidr_block = "10.0.0.0/16"
      azs        = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
    "eu-west-1" = {
      cidr_block = "10.1.0.0/16"
      azs        = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
    }
    "ap-southeast-1" = {
      cidr_block = "10.2.0.0/16"
      azs        = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
    }
  }
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "enable_transit_gateway" {
  description = "Enable Transit Gateway for VPC connectivity"
  type        = bool
  default     = true
}

# ============================================================================
# PROVIDER CONFIGURATION (Multi-Region)
# ============================================================================

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "Infrastructure"
    }
  }
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "Infrastructure"
    }
  }
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "Infrastructure"
    }
  }
}

# ============================================================================
# VPC MODULE (Reusable across all regions)
# ============================================================================

module "vpc_us_east_1" {
  source = "./modules/vpc"
  providers = {
    aws = aws.us_east_1
  }

  vpc_name              = "${var.project_name}-${var.environment}-us-east-1"
  cidr_block            = var.regions["us-east-1"].cidr_block
  availability_zones    = var.regions["us-east-1"].azs
  enable_flow_logs      = var.enable_flow_logs
  flow_logs_bucket_name = "${var.project_name}-vpc-flow-logs-us-east-1"
  
  tags = {
    Region = "us-east-1"
    Role   = "Primary"
  }
}

module "vpc_eu_west_1" {
  source = "./modules/vpc"
  providers = {
    aws = aws.eu_west_1
  }

  vpc_name              = "${var.project_name}-${var.environment}-eu-west-1"
  cidr_block            = var.regions["eu-west-1"].cidr_block
  availability_zones    = var.regions["eu-west-1"].azs
  enable_flow_logs      = var.enable_flow_logs
  flow_logs_bucket_name = "${var.project_name}-vpc-flow-logs-eu-west-1"
  
  tags = {
    Region = "eu-west-1"
    Role   = "Secondary"
    Compliance = "GDPR"
  }
}

module "vpc_ap_southeast_1" {
  source = "./modules/vpc"
  providers = {
    aws = aws.ap_southeast_1
  }

  vpc_name              = "${var.project_name}-${var.environment}-ap-southeast-1"
  cidr_block            = var.regions["ap-southeast-1"].cidr_block
  availability_zones    = var.regions["ap-southeast-1"].azs
  enable_flow_logs      = var.enable_flow_logs
  flow_logs_bucket_name = "${var.project_name}-vpc-flow-logs-ap-southeast-1"
  
  tags = {
    Region = "ap-southeast-1"
    Role   = "Tertiary"
  }
}

# ============================================================================
# TRANSIT GATEWAY (us-east-1 as hub)
# ============================================================================

resource "aws_ec2_transit_gateway" "main" {
  provider = aws.us_east_1

  description                     = "Multi-region transit gateway"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support               = "enable"
  auto_accept_shared_attachments = "enable"

  tags = {
    Name = "${var.project_name}-tgw"
  }
}

# Transit Gateway VPC Attachments
resource "aws_ec2_transit_gateway_vpc_attachment" "us_east_1" {
  provider = aws.us_east_1

  subnet_ids         = module.vpc_us_east_1.private_subnet_ids
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = module.vpc_us_east_1.vpc_id
  dns_support        = "enable"

  tags = {
    Name = "${var.project_name}-tgw-attachment-us-east-1"
  }
}

# ============================================================================
# VPC PEERING (Cross-Region)
# ============================================================================

# us-east-1 <-> eu-west-1 peering
resource "aws_vpc_peering_connection" "us_to_eu" {
  provider = aws.us_east_1

  vpc_id      = module.vpc_us_east_1.vpc_id
  peer_vpc_id = module.vpc_eu_west_1.vpc_id
  peer_region = "eu-west-1"
  auto_accept = false

  tags = {
    Name = "us-east-1-to-eu-west-1"
  }
}

resource "aws_vpc_peering_connection_accepter" "us_to_eu" {
  provider = aws.eu_west_1

  vpc_peering_connection_id = aws_vpc_peering_connection.us_to_eu.id
  auto_accept               = true

  tags = {
    Name = "us-east-1-to-eu-west-1-accepter"
  }
}

# us-east-1 <-> ap-southeast-1 peering
resource "aws_vpc_peering_connection" "us_to_ap" {
  provider = aws.us_east_1

  vpc_id      = module.vpc_us_east_1.vpc_id
  peer_vpc_id = module.vpc_ap_southeast_1.vpc_id
  peer_region = "ap-southeast-1"
  auto_accept = false

  tags = {
    Name = "us-east-1-to-ap-southeast-1"
  }
}

resource "aws_vpc_peering_connection_accepter" "us_to_ap" {
  provider = aws.ap_southeast_1

  vpc_peering_connection_id = aws_vpc_peering_connection.us_to_ap.id
  auto_accept               = true

  tags = {
    Name = "us-east-1-to-ap-southeast-1-accepter"
  }
}

# ============================================================================
# SECURITY GROUPS
# ============================================================================

# ALB Security Group (accepts HTTPS from internet)
resource "aws_security_group" "alb" {
  provider = aws.us_east_1

  name_prefix = "${var.project_name}-alb-"
  description = "Security group for Application Load Balancer"
  vpc_id      = module.vpc_us_east_1.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Application Security Group (accepts from ALB only)
resource "aws_security_group" "app" {
  provider = aws.us_east_1

  name_prefix = "${var.project_name}-app-"
  description = "Security group for application tier"
  vpc_id      = module.vpc_us_east_1.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Database Security Group (accepts from app tier only)
resource "aws_security_group" "database" {
  provider = aws.us_east_1

  name_prefix = "${var.project_name}-db-"
  description = "Security group for database tier"
  vpc_id      = module.vpc_us_east_1.vpc_id

  ingress {
    description     = "PostgreSQL from app tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# VPC MODULE DEFINITION (modules/vpc/main.tf)
# ============================================================================

# NOTE: This would be in a separate file modules/vpc/main.tf
# Included here for completeness

/*
variable "vpc_name" { type = string }
variable "cidr_block" { type = string }
variable "availability_zones" { type = list(string) }
variable "enable_flow_logs" { type = bool }
variable "flow_logs_bucket_name" { type = string }
variable "tags" { type = map(string) }

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = var.vpc_name
  })
}

# Public Subnets (one per AZ)
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-public-${var.availability_zones[count.index]}"
    Tier = "Public"
  })
}

# Private App Subnets (one per AZ)
resource "aws_subnet" "private_app" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index + 11)
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-app-${var.availability_zones[count.index]}"
    Tier = "PrivateApp"
  })
}

# Private Data Subnets (one per AZ)
resource "aws_subnet" "private_data" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index + 21)
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-data-${var.availability_zones[count.index]}"
    Tier = "PrivateData"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-igw"
  })
}

# NAT Gateways (one per AZ for high availability)
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-nat-eip-${var.availability_zones[count.index]}"
  })
}

resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-nat-${var.availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-public-rt"
  })
}

resource "aws_route_table" "private_app" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-app-rt-${var.availability_zones[count.index]}"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_app" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# VPC Flow Logs
resource "aws_s3_bucket" "flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = var.flow_logs_bucket_name

  tags = merge(var.tags, {
    Name = var.flow_logs_bucket_name
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  log_destination_type = "s3"
  log_destination = aws_s3_bucket.flow_logs[0].arn

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-flow-logs"
  })
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "database_subnet_ids" {
  value = aws_subnet.private_data[*].id
}
*/

# ============================================================================
# OUTPUTS
# ============================================================================

output "vpc_ids" {
  description = "VPC IDs for all regions"
  value = {
    us_east_1      = module.vpc_us_east_1.vpc_id
    eu_west_1      = module.vpc_eu_west_1.vpc_id
    ap_southeast_1 = module.vpc_ap_southeast_1.vpc_id
  }
}

output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.main.id
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    alb      = aws_security_group.alb.id
    app      = aws_security_group.app.id
    database = aws_security_group.database.id
  }
}
