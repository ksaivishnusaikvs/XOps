# Challenge 11: AWS Infrastructure & Services - Implementation

This directory contains production-ready implementation files for AWS infrastructure deployment and management.

## 📁 Files Overview

### 1. **multi-region-vpc.tf**
Terraform configuration for multi-region VPC infrastructure.

**Features:**
- VPC creation across 3 AWS regions (us-east-1, eu-west-1, ap-southeast-1)
- Proper CIDR allocation with /16 VPCs and /24 subnets
- 3-tier architecture (Public, Private App, Private Data subnets)
- Transit Gateway for centralized connectivity
- VPC peering for cross-region communication
- Layered security groups (ALB, App, Database)
- VPC Flow Logs to S3 with lifecycle policies
- NAT Gateways for high availability

**Usage:**
```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=tfplan

# Apply infrastructure
terraform apply tfplan

# Destroy (when needed)
terraform destroy
```

### 2. **autoscaling-stack.yaml**
CloudFormation template for Auto-Scaling Groups with Application Load Balancer.

**Features:**
- Application Load Balancer with HTTPS support
- Auto Scaling Group with mixed instance types
- 80% Spot Instances for cost optimization
- Target tracking scaling policies
- Health checks and connection draining
- IAM roles for EC2 instances
- CloudWatch alarms for monitoring
- User data script for instance initialization

**Deployment:**
```bash
# Validate template
aws cloudformation validate-template --template-body file://autoscaling-stack.yaml

# Create stack
aws cloudformation create-stack \
  --stack-name production-autoscaling \
  --template-body file://autoscaling-stack.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=vpc-xxx \
    ParameterKey=PublicSubnets,ParameterValue=subnet-xxx\\,subnet-yyy \
    ParameterKey=PrivateSubnets,ParameterValue=subnet-aaa\\,subnet-bbb \
  --capabilities CAPABILITY_NAMED_IAM

# Update stack
aws cloudformation update-stack \
  --stack-name production-autoscaling \
  --template-body file://autoscaling-stack.yaml \
  --capabilities CAPABILITY_NAMED_IAM

# Delete stack
aws cloudformation delete-stack --stack-name production-autoscaling
```

### 3. **cost-optimizer.py**
Python Lambda function for automated AWS cost optimization.

**Features:**
- Identifies and deletes unattached EBS volumes
- Releases orphaned Elastic IPs
- Archives old snapshots (>90 days)
- Reports on untagged resources
- Analyzes under-utilized EC2 instances (<10% CPU)
- Generates cost optimization reports
- SNS notifications for alerts
- Dry-run mode for testing

**Environment Variables:**
- `SNS_TOPIC_ARN`: SNS topic for notifications
- `DRY_RUN`: Set to 'true' for testing without making changes
- `MIN_DAYS_BEFORE_DELETE`: Minimum age before deleting resources (default: 7)

**Deployment:**
```bash
# Create deployment package
zip -r cost-optimizer.zip cost-optimizer.py

# Create Lambda function
aws lambda create-function \
  --function-name cost-optimizer \
  --runtime python3.9 \
  --role arn:aws:iam::ACCOUNT_ID:role/LambdaExecutionRoleForCostOptimizer \
  --handler cost-optimizer.lambda_handler \
  --zip-file fileb://cost-optimizer.zip \
  --timeout 300 \
  --memory-size 512 \
  --environment Variables={DRY_RUN=false,MIN_DAYS_BEFORE_DELETE=7,SNS_TOPIC_ARN=arn:aws:sns:us-east-1:xxx:cost-alerts}

# Schedule with EventBridge (daily at 2 AM)
aws events put-rule \
  --name cost-optimizer-daily \
  --schedule-expression "cron(0 2 * * ? *)"

aws events put-targets \
  --rule cost-optimizer-daily \
  --targets "Id"="1","Arn"="arn:aws:lambda:us-east-1:ACCOUNT_ID:function:cost-optimizer"

# Test locally
python3 cost-optimizer.py
```

### 4. **aws-resource-manager.sh**
Comprehensive Bash script for AWS resource management.

**Features:**
- EC2 instance management (start/stop/list)
- RDS snapshot creation and listing
- S3 versioning, lifecycle, and encryption management
- Security group auditing (checks for 0.0.0.0/0 on SSH/RDP)
- Resource tagging compliance checks
- Cost report generation
- Interactive menu system
- Logging and error handling

**Usage:**
```bash
# Make executable
chmod +x aws-resource-manager.sh

# Run interactively
./aws-resource-manager.sh

# Run specific commands
export AWS_PROFILE=production
export AWS_REGION=us-east-1
export DRY_RUN=false

# Stop dev instances
./aws-resource-manager.sh <<< "3
Environment:development"
```

### 5. **iam-policies.json**
Collection of production-ready IAM policies.

**Included Policies:**
- **DeveloperRolePolicy**: Read-only prod, full dev access
- **EC2AdminRolePolicy**: EC2 admin with MFA for termination
- **RDSAdminRolePolicy**: RDS admin with encryption enforcement
- **S3AdminRolePolicy**: S3 admin with encryption requirements
- **EC2InstanceRoleForS3Access**: EC2 role for S3 and Secrets Manager
- **LambdaExecutionRoleForCostOptimizer**: Lambda role for cost optimizer
- **SecurityAuditorRolePolicy**: Read-only security access
- **CI_CD_DeploymentRolePolicy**: ECR and ECS deployment access
- **EnforceMFAPolicy**: Enforces MFA on all actions
- **RestrictRegionPolicy**: Limits to approved regions only
- **RequireResourceTagsPolicy**: Enforces mandatory tags

**Usage:**
```bash
# Create IAM policy
aws iam create-policy \
  --policy-name DeveloperRolePolicy \
  --policy-document file://<(jq '.Policies.DeveloperRolePolicy' iam-policies.json)

# Attach to role
aws iam attach-role-policy \
  --role-name developer-role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/DeveloperRolePolicy

# Create S3 bucket policy
aws s3api put-bucket-policy \
  --bucket my-secure-bucket \
  --policy file://<(jq '.S3BucketPolicies.SecureS3BucketPolicy' iam-policies.json | sed 's/BUCKET_NAME/my-secure-bucket/g')
```

### 6. **cloudwatch-dashboard.json**
Comprehensive CloudWatch dashboard configuration.

**Dashboard Sections:**
1. **Application Load Balancer Metrics**
   - Response time (Average and P99)
   - Request count
   - HTTP status codes (2xx, 4xx, 5xx)
   - Target health

2. **EC2 and Auto Scaling Metrics**
   - CPU utilization with scaling thresholds
   - Auto Scaling Group capacity
   - Network traffic

3. **RDS Metrics**
   - CPU utilization
   - Database connections
   - Read/Write latency
   - Freeable memory

4. **Lambda Metrics**
   - Invocations
   - Errors and throttles
   - Duration (Average and P99)

5. **DynamoDB Metrics**
   - User and system errors

6. **Custom Business Metrics**
   - Orders per minute
   - Revenue per minute
   - Cart abandonment rate

**Deployment:**
```bash
# Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name production-infrastructure \
  --dashboard-body file://cloudwatch-dashboard.json

# View dashboard
# Navigate to: CloudWatch > Dashboards > production-infrastructure
```

### 7. **aws-automation.sh**
AWS CLI automation scripts for common operations.

**Features:**
- Multi-region RDS snapshot replication
- Automated AMI backup creation
- Old AMI cleanup (with retention policy)
- S3 cross-region replication setup
- Route 53 health check creation
- Lambda function deployment
- Security group backup
- EC2 instance scheduler (dev environments)
- Cost allocation tag enforcement
- Infrastructure reporting

**Usage:**
```bash
# Make executable
chmod +x aws-automation.sh

# Run interactively
./aws-automation.sh

# Schedule with cron
# Daily AMI backups at 2 AM
0 2 * * * /path/to/aws-automation.sh <<< "2
Environment:production
us-east-1"

# Stop dev instances at 7 PM
0 19 * * 1-5 /path/to/aws-automation.sh <<< "8
stop
Environment:development"

# Start dev instances at 8 AM
0 8 * * 1-5 /path/to/aws-automation.sh <<< "8
start
Environment:development"
```

## 🚀 Quick Start Guide

### Prerequisites
```bash
# Install required tools
brew install terraform awscli jq  # macOS
# or
apt-get install terraform awscli jq  # Ubuntu

# Configure AWS credentials
aws configure
```

### Deployment Order

1. **VPC Infrastructure** (Week 1)
   ```bash
   cd implementation/
   terraform init
   terraform apply -target=module.vpc_us_east_1
   ```

2. **Security Groups** (Week 1)
   ```bash
   terraform apply -target=aws_security_group.alb
   terraform apply -target=aws_security_group.app
   terraform apply -target=aws_security_group.database
   ```

3. **Auto-Scaling** (Week 2)
   ```bash
   aws cloudformation create-stack \
     --stack-name production-autoscaling \
     --template-body file://autoscaling-stack.yaml \
     --parameters file://parameters.json \
     --capabilities CAPABILITY_NAMED_IAM
   ```

4. **IAM Policies** (Week 2)
   ```bash
   # Create all necessary IAM roles and policies
   for policy in DeveloperRolePolicy EC2AdminRolePolicy RDSAdminRolePolicy; do
     aws iam create-policy \
       --policy-name $policy \
       --policy-document file://<(jq ".Policies.$policy" iam-policies.json)
   done
   ```

5. **Lambda Cost Optimizer** (Week 3)
   ```bash
   zip cost-optimizer.zip cost-optimizer.py
   aws lambda create-function \
     --function-name cost-optimizer \
     --runtime python3.9 \
     --role arn:aws:iam::ACCOUNT_ID:role/LambdaExecutionRoleForCostOptimizer \
     --handler cost-optimizer.lambda_handler \
     --zip-file fileb://cost-optimizer.zip
   ```

6. **CloudWatch Dashboard** (Week 3)
   ```bash
   aws cloudwatch put-dashboard \
     --dashboard-name production-infrastructure \
     --dashboard-body file://cloudwatch-dashboard.json
   ```

## 📊 Monitoring and Validation

### Infrastructure Validation
```bash
# Run resource manager audit
./aws-resource-manager.sh
# Choose option 9: Audit Security Groups
# Choose option 10: Audit Resource Tags

# Generate infrastructure report
./aws-automation.sh
# Choose option 10: Generate Infrastructure Report
```

### Cost Monitoring
```bash
# Run cost optimizer in dry-run mode
DRY_RUN=true python3 cost-optimizer.py

# Check estimated savings
aws ce get-cost-forecast \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --metric BLENDED_COST \
  --granularity MONTHLY
```

## 🔒 Security Best Practices

1. **Never commit AWS credentials** to Git
2. **Use MFA** for all privileged operations
3. **Enable CloudTrail** in all regions
4. **Encrypt all data** at rest and in transit
5. **Follow least privilege** for IAM policies
6. **Regular security audits** with aws-resource-manager.sh
7. **Enable GuardDuty** for threat detection

## 💰 Cost Optimization Tips

1. **Run cost-optimizer Lambda** daily
2. **Use Spot Instances** for non-critical workloads (see autoscaling-stack.yaml)
3. **Schedule dev environments** to stop after hours (see aws-automation.sh)
4. **Implement S3 lifecycle policies** for log archival
5. **Purchase Reserved Instances** for steady-state workloads
6. **Right-size instances** based on CloudWatch metrics

## 🆘 Troubleshooting

### Common Issues

**Terraform State Lock:**
```bash
# Remove stuck lock (use carefully!)
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"terraform-state-prod/multi-region-vpc/terraform.tfstate"}}'
```

**CloudFormation Stack Stuck:**
```bash
# Cancel update
aws cloudformation cancel-update-stack --stack-name production-autoscaling

# Continue rollback
aws cloudformation continue-update-rollback --stack-name production-autoscaling
```

**Lambda Timeout:**
```bash
# Increase timeout
aws lambda update-function-configuration \
  --function-name cost-optimizer \
  --timeout 600
```

## 📚 Additional Resources

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/)
- [AWS Cost Optimization Guide](https://aws.amazon.com/pricing/cost-optimization/)

## 📝 License

These scripts are provided as-is for educational and production use. Customize as needed for your environment.

## ✅ Validation Checklist

Before deploying to production:

- [ ] All region constraints configured
- [ ] MFA enforcement enabled
- [ ] Required tags policy applied
- [ ] VPC Flow Logs enabled
- [ ] CloudTrail enabled in all regions
- [ ] GuardDuty enabled
- [ ] Security Hub enabled
- [ ] Cost Explorer enabled
- [ ] Backup retention configured
- [ ] Disaster recovery tested
- [ ] Documentation updated
- [ ] Team trained on new infrastructure

---

**Last Updated:** January 19, 2026  
**Maintained By:** DevOps Team
