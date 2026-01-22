# AWS Transit Gateway for Multi-VPC and Multi-Region Connectivity
resource "aws_ec2_transit_gateway" "main" {
  description                     = "${var.environment} Transit Gateway"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support               = "enable"
  amazon_side_asn                = 64512

  tags = {
    Name        = "${var.environment}-tgw"
    Environment = var.environment
  }
}

# Transit Gateway Attachment for Production VPC
resource "aws_ec2_transit_gateway_vpc_attachment" "production" {
  subnet_ids         = aws_subnet.private_app[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.main.id
  dns_support        = "enable"

  tags = {
    Name = "${var.environment}-tgw-attachment"
  }
}

# Transit Gateway Attachment for Development VPC (example)
resource "aws_ec2_transit_gateway_vpc_attachment" "development" {
  count = var.enable_dev_vpc ? 1 : 0

  subnet_ids         = aws_subnet.dev_private[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.development[0].id
  dns_support        = "enable"

  tags = {
    Name = "development-tgw-attachment"
  }
}

# Transit Gateway Route Table
resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = {
    Name = "${var.environment}-tgw-rt"
  }
}

# VPN Customer Gateway (on-premises)
resource "aws_customer_gateway" "on_prem" {
  bgp_asn    = 65000
  ip_address = var.on_prem_vpn_ip
  type       = "ipsec.1"

  tags = {
    Name = "on-premises-cgw"
  }
}

# Site-to-Site VPN Connection
resource "aws_vpn_connection" "main" {
  customer_gateway_id = aws_customer_gateway.on_prem.id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type                = aws_customer_gateway.on_prem.type

  # Redundant tunnels for HA
  tunnel1_inside_cidr   = "169.254.10.0/30"
  tunnel2_inside_cidr   = "169.254.11.0/30"
  tunnel1_preshared_key = var.vpn_preshared_key_1
  tunnel2_preshared_key = var.vpn_preshared_key_2

  tags = {
    Name = "${var.environment}-vpn"
  }
}

# AWS PrivateLink Endpoint for S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.private_data.id],
    aws_route_table.private_app[*].id
  )

  tags = {
    Name = "${var.environment}-s3-endpoint"
  }
}

# VPC Endpoint for AWS Systems Manager (for bastion-less access)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.environment}-ssm-endpoint"
  }
}

# VPC Endpoint for EC2 Messages (required for SSM)
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.environment}-ec2messages-endpoint"
  }
}

# VPC Endpoint for SSM Messages
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.environment}-ssmmessages-endpoint"
  }
}

# Direct Connect Gateway (for high-bandwidth on-prem connectivity)
# Note: Actual Direct Connect circuit must be provisioned separately
resource "aws_dx_gateway" "main" {
  count = var.enable_direct_connect ? 1 : 0

  name            = "${var.environment}-dx-gateway"
  amazon_side_asn = "64512"
}

resource "aws_dx_gateway_association" "tgw" {
  count = var.enable_direct_connect ? 1 : 0

  dx_gateway_id         = aws_dx_gateway.main[0].id
  associated_gateway_id = aws_ec2_transit_gateway.main.id

  allowed_prefixes = [
    var.vpc_cidr,
  ]
}

# Variables
variable "enable_dev_vpc" {
  type    = bool
  default = false
}

variable "enable_direct_connect" {
  type    = bool
  default = false
}

variable "on_prem_vpn_ip" {
  type        = string
  description = "Public IP of on-premises VPN gateway"
}

variable "vpn_preshared_key_1" {
  type        = string
  sensitive   = true
  description = "Pre-shared key for VPN tunnel 1"
}

variable "vpn_preshared_key_2" {
  type        = string
  sensitive   = true
  description = "Pre-shared key for VPN tunnel 2"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# Outputs
output "transit_gateway_id" {
  value = aws_ec2_transit_gateway.main.id
}

output "vpn_connection_id" {
  value = aws_vpn_connection.main.id
}

output "vpc_endpoints" {
  value = {
    s3          = aws_vpc_endpoint.s3.id
    ssm         = aws_vpc_endpoint.ssm.id
    ec2messages = aws_vpc_endpoint.ec2messages.id
    ssmmessages = aws_vpc_endpoint.ssmmessages.id
  }
}
