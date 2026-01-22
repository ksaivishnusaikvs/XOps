"""
AWS Cost Optimizer Lambda Function
Automated cost optimization for AWS infrastructure

Features:
- Identify and delete unattached EBS volumes
- Release orphaned Elastic IPs
- Archive old snapshots to reduce costs
- Report on untagged resources
- Analyze under-utilized EC2 instances
- Generate weekly cost optimization reports

Author: DevOps Team
Version: 1.0.0
"""

import boto3
import json
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ec2_client = boto3.client('ec2')
cloudwatch_client = boto3.client('cloudwatch')
sns_client = boto3.client('sns')
cost_explorer_client = boto3.client('ce')

# Environment variables
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
DRY_RUN = os.environ.get('DRY_RUN', 'false').lower() == 'true'
MIN_DAYS_BEFORE_DELETE = int(os.environ.get('MIN_DAYS_BEFORE_DELETE', '7'))

# ============================================================================
# UNATTACHED EBS VOLUMES
# ============================================================================

def find_unattached_volumes() -> List[Dict[str, Any]]:
    """Find all unattached EBS volumes."""
    logger.info("Searching for unattached EBS volumes...")
    
    unattached_volumes = []
    
    try:
        volumes = ec2_client.describe_volumes(
            Filters=[
                {'Name': 'status', 'Values': ['available']}
            ]
        )
        
        for volume in volumes['Volumes']:
            volume_age = (datetime.now(volume['CreateTime'].tzinfo) - volume['CreateTime']).days
            
            if volume_age >= MIN_DAYS_BEFORE_DELETE:
                volume_info = {
                    'VolumeId': volume['VolumeId'],
                    'Size': volume['Size'],
                    'VolumeType': volume['VolumeType'],
                    'CreateTime': volume['CreateTime'].isoformat(),
                    'AgeDays': volume_age,
                    'AvailabilityZone': volume['AvailabilityZone'],
                    'Tags': volume.get('Tags', [])
                }
                
                # Calculate monthly cost (gp3: $0.08/GB/month)
                monthly_cost = volume['Size'] * 0.08
                volume_info['MonthlyCost'] = round(monthly_cost, 2)
                
                unattached_volumes.append(volume_info)
        
        logger.info(f"Found {len(unattached_volumes)} unattached volumes")
        
    except Exception as e:
        logger.error(f"Error finding unattached volumes: {str(e)}")
    
    return unattached_volumes


def delete_unattached_volumes(volumes: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Delete unattached EBS volumes."""
    results = {
        'deleted': [],
        'failed': [],
        'total_savings': 0
    }
    
    for volume in volumes:
        volume_id = volume['VolumeId']
        
        if DRY_RUN:
            logger.info(f"[DRY RUN] Would delete volume: {volume_id}")
            results['deleted'].append(volume_id)
            results['total_savings'] += volume['MonthlyCost']
        else:
            try:
                # Create snapshot before deletion (safety measure)
                snapshot = ec2_client.create_snapshot(
                    VolumeId=volume_id,
                    Description=f"Pre-deletion snapshot of {volume_id}",
                    TagSpecifications=[{
                        'ResourceType': 'snapshot',
                        'Tags': [
                            {'Key': 'Name', 'Value': f'{volume_id}-pre-deletion'},
                            {'Key': 'AutoCreated', 'Value': 'true'},
                            {'Key': 'OriginalVolumeId', 'Value': volume_id}
                        ]
                    }]
                )
                
                logger.info(f"Created safety snapshot: {snapshot['SnapshotId']}")
                
                # Delete the volume
                ec2_client.delete_volume(VolumeId=volume_id)
                logger.info(f"Deleted volume: {volume_id}")
                
                results['deleted'].append(volume_id)
                results['total_savings'] += volume['MonthlyCost']
                
            except Exception as e:
                logger.error(f"Failed to delete volume {volume_id}: {str(e)}")
                results['failed'].append({
                    'VolumeId': volume_id,
                    'Error': str(e)
                })
    
    return results


# ============================================================================
# ORPHANED ELASTIC IPs
# ============================================================================

def find_orphaned_eips() -> List[Dict[str, Any]]:
    """Find Elastic IPs not associated with any resource."""
    logger.info("Searching for orphaned Elastic IPs...")
    
    orphaned_eips = []
    
    try:
        addresses = ec2_client.describe_addresses()
        
        for address in addresses['Addresses']:
            # EIP is orphaned if it's not associated with an instance or network interface
            if 'AssociationId' not in address:
                eip_info = {
                    'PublicIp': address['PublicIp'],
                    'AllocationId': address['AllocationId'],
                    'Domain': address['Domain'],
                    'Tags': address.get('Tags', [])
                }
                
                # Orphaned EIP costs $0.005/hour = $3.60/month
                eip_info['MonthlyCost'] = 3.60
                
                orphaned_eips.append(eip_info)
        
        logger.info(f"Found {len(orphaned_eips)} orphaned Elastic IPs")
        
    except Exception as e:
        logger.error(f"Error finding orphaned EIPs: {str(e)}")
    
    return orphaned_eips


def release_orphaned_eips(eips: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Release orphaned Elastic IPs."""
    results = {
        'released': [],
        'failed': [],
        'total_savings': 0
    }
    
    for eip in eips:
        allocation_id = eip['AllocationId']
        
        if DRY_RUN:
            logger.info(f"[DRY RUN] Would release EIP: {eip['PublicIp']}")
            results['released'].append(eip['PublicIp'])
            results['total_savings'] += eip['MonthlyCost']
        else:
            try:
                ec2_client.release_address(AllocationId=allocation_id)
                logger.info(f"Released EIP: {eip['PublicIp']}")
                
                results['released'].append(eip['PublicIp'])
                results['total_savings'] += eip['MonthlyCost']
                
            except Exception as e:
                logger.error(f"Failed to release EIP {eip['PublicIp']}: {str(e)}")
                results['failed'].append({
                    'PublicIp': eip['PublicIp'],
                    'Error': str(e)
                })
    
    return results


# ============================================================================
# OLD SNAPSHOTS
# ============================================================================

def find_old_snapshots(days_old: int = 90) -> List[Dict[str, Any]]:
    """Find snapshots older than specified days."""
    logger.info(f"Searching for snapshots older than {days_old} days...")
    
    old_snapshots = []
    cutoff_date = datetime.now(datetime.now().astimezone().tzinfo) - timedelta(days=days_old)
    
    try:
        snapshots = ec2_client.describe_snapshots(OwnerIds=['self'])
        
        for snapshot in snapshots['Snapshots']:
            if snapshot['StartTime'] < cutoff_date:
                snapshot_info = {
                    'SnapshotId': snapshot['SnapshotId'],
                    'VolumeId': snapshot.get('VolumeId', 'N/A'),
                    'VolumeSize': snapshot['VolumeSize'],
                    'StartTime': snapshot['StartTime'].isoformat(),
                    'AgeDays': (datetime.now(snapshot['StartTime'].tzinfo) - snapshot['StartTime']).days,
                    'Description': snapshot.get('Description', ''),
                    'Tags': snapshot.get('Tags', [])
                }
                
                # Snapshot cost: $0.05/GB/month
                monthly_cost = snapshot['VolumeSize'] * 0.05
                snapshot_info['MonthlyCost'] = round(monthly_cost, 2)
                
                old_snapshots.append(snapshot_info)
        
        logger.info(f"Found {len(old_snapshots)} old snapshots")
        
    except Exception as e:
        logger.error(f"Error finding old snapshots: {str(e)}")
    
    return old_snapshots


def archive_old_snapshots(snapshots: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Tag old snapshots for archival (deletion would be in separate process)."""
    results = {
        'tagged': [],
        'failed': []
    }
    
    for snapshot in snapshots:
        snapshot_id = snapshot['SnapshotId']
        
        try:
            ec2_client.create_tags(
                Resources=[snapshot_id],
                Tags=[
                    {'Key': 'CostOptimization', 'Value': 'ToBeArchived'},
                    {'Key': 'ArchiveDate', 'Value': datetime.now().isoformat()}
                ]
            )
            
            logger.info(f"Tagged snapshot for archival: {snapshot_id}")
            results['tagged'].append(snapshot_id)
            
        except Exception as e:
            logger.error(f"Failed to tag snapshot {snapshot_id}: {str(e)}")
            results['failed'].append({
                'SnapshotId': snapshot_id,
                'Error': str(e)
            })
    
    return results


# ============================================================================
# UNTAGGED RESOURCES
# ============================================================================

def find_untagged_resources() -> Dict[str, List[str]]:
    """Find resources missing required tags."""
    logger.info("Searching for untagged resources...")
    
    required_tags = ['Environment', 'CostCenter', 'Owner', 'Project']
    untagged_resources = {
        'instances': [],
        'volumes': [],
        's3_buckets': []
    }
    
    try:
        # Check EC2 instances
        instances = ec2_client.describe_instances()
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
                missing_tags = [tag for tag in required_tags if tag not in tags]
                
                if missing_tags:
                    untagged_resources['instances'].append({
                        'InstanceId': instance['InstanceId'],
                        'MissingTags': missing_tags
                    })
        
        # Check EBS volumes
        volumes = ec2_client.describe_volumes()
        for volume in volumes['Volumes']:
            tags = {tag['Key']: tag['Value'] for tag in volume.get('Tags', [])}
            missing_tags = [tag for tag in required_tags if tag not in tags]
            
            if missing_tags:
                untagged_resources['volumes'].append({
                    'VolumeId': volume['VolumeId'],
                    'MissingTags': missing_tags
                })
        
        logger.info(f"Found {len(untagged_resources['instances'])} untagged instances")
        logger.info(f"Found {len(untagged_resources['volumes'])} untagged volumes")
        
    except Exception as e:
        logger.error(f"Error finding untagged resources: {str(e)}")
    
    return untagged_resources


# ============================================================================
# UNDERUTILIZED EC2 INSTANCES
# ============================================================================

def analyze_ec2_utilization() -> List[Dict[str, Any]]:
    """Analyze EC2 instances with low CPU utilization."""
    logger.info("Analyzing EC2 instance utilization...")
    
    underutilized_instances = []
    end_time = datetime.now()
    start_time = end_time - timedelta(days=7)
    
    try:
        instances = ec2_client.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
        )
        
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                
                # Get average CPU utilization for last 7 days
                cpu_stats = cloudwatch_client.get_metric_statistics(
                    Namespace='AWS/EC2',
                    MetricName='CPUUtilization',
                    Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,  # 1 hour
                    Statistics=['Average']
                )
                
                if cpu_stats['Datapoints']:
                    avg_cpu = sum(dp['Average'] for dp in cpu_stats['Datapoints']) / len(cpu_stats['Datapoints'])
                    
                    # Flag instances with < 10% average CPU
                    if avg_cpu < 10:
                        underutilized_instances.append({
                            'InstanceId': instance_id,
                            'InstanceType': instance['InstanceType'],
                            'AvgCpuUtilization': round(avg_cpu, 2),
                            'LaunchTime': instance['LaunchTime'].isoformat(),
                            'Tags': instance.get('Tags', [])
                        })
        
        logger.info(f"Found {len(underutilized_instances)} underutilized instances")
        
    except Exception as e:
        logger.error(f"Error analyzing EC2 utilization: {str(e)}")
    
    return underutilized_instances


# ============================================================================
# COST REPORT GENERATION
# ============================================================================

def generate_cost_report(
    volume_results: Dict[str, Any],
    eip_results: Dict[str, Any],
    snapshot_results: Dict[str, Any],
    untagged: Dict[str, List[str]],
    underutilized: List[Dict[str, Any]]
) -> str:
    """Generate comprehensive cost optimization report."""
    
    total_savings = volume_results['total_savings'] + eip_results['total_savings']
    
    report = f"""
    ╔══════════════════════════════════════════════════════════════════════════╗
    ║              AWS COST OPTIMIZATION REPORT                                ║
    ║              Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}                            ║
    ╚══════════════════════════════════════════════════════════════════════════╝
    
    📊 SUMMARY
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Total Monthly Savings:        ${total_savings:,.2f}
    Total Annual Savings:         ${total_savings * 12:,.2f}
    
    💾 UNATTACHED EBS VOLUMES
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Volumes Deleted:              {len(volume_results['deleted'])}
    Volumes Failed:               {len(volume_results['failed'])}
    Monthly Savings:              ${volume_results['total_savings']:,.2f}
    
    Deleted Volumes:
    {chr(10).join(f'    - {vol}' for vol in volume_results['deleted'][:10])}
    {f"    ... and {len(volume_results['deleted']) - 10} more" if len(volume_results['deleted']) > 10 else ''}
    
    🌐 ORPHANED ELASTIC IPs
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    EIPs Released:                {len(eip_results['released'])}
    EIPs Failed:                  {len(eip_results['failed'])}
    Monthly Savings:              ${eip_results['total_savings']:,.2f}
    
    Released EIPs:
    {chr(10).join(f'    - {eip}' for eip in eip_results['released'])}
    
    📸 OLD SNAPSHOTS
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Snapshots Tagged for Archival: {len(snapshot_results['tagged'])}
    
    🏷️ UNTAGGED RESOURCES
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Untagged Instances:           {len(untagged['instances'])}
    Untagged Volumes:             {len(untagged['volumes'])}
    
    ⚠️ UNDERUTILIZED EC2 INSTANCES
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Low CPU Utilization (<10%):   {len(underutilized)}
    
    Recommendations:
    {chr(10).join(f'    - {inst["InstanceId"]} ({inst["InstanceType"]}): {inst["AvgCpuUtilization"]}% CPU' for inst in underutilized[:5])}
    {f"    ... and {len(underutilized) - 5} more" if len(underutilized) > 5 else ''}
    
    📋 NEXT STEPS
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    1. Review underutilized instances and consider downsizing
    2. Tag all untagged resources for cost allocation
    3. Review old snapshots and archive to S3 Glacier if needed
    4. Consider Reserved Instances for steady-state workloads
    
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """
    
    return report


def send_notification(report: str):
    """Send cost optimization report via SNS."""
    if not SNS_TOPIC_ARN:
        logger.warning("SNS_TOPIC_ARN not configured, skipping notification")
        return
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='AWS Cost Optimization Report',
            Message=report
        )
        logger.info("Notification sent successfully")
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")


# ============================================================================
# LAMBDA HANDLER
# ============================================================================

def lambda_handler(event, context):
    """Main Lambda handler function."""
    logger.info("Starting AWS cost optimization...")
    logger.info(f"DRY_RUN mode: {DRY_RUN}")
    
    try:
        # Find and process unattached volumes
        unattached_volumes = find_unattached_volumes()
        volume_results = delete_unattached_volumes(unattached_volumes)
        
        # Find and release orphaned EIPs
        orphaned_eips = find_orphaned_eips()
        eip_results = release_orphaned_eips(orphaned_eips)
        
        # Find and tag old snapshots
        old_snapshots = find_old_snapshots(days_old=90)
        snapshot_results = archive_old_snapshots(old_snapshots)
        
        # Find untagged resources
        untagged_resources = find_untagged_resources()
        
        # Analyze EC2 utilization
        underutilized_instances = analyze_ec2_utilization()
        
        # Generate and send report
        report = generate_cost_report(
            volume_results,
            eip_results,
            snapshot_results,
            untagged_resources,
            underutilized_instances
        )
        
        logger.info(report)
        send_notification(report)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization completed successfully',
                'total_savings': volume_results['total_savings'] + eip_results['total_savings'],
                'volumes_deleted': len(volume_results['deleted']),
                'eips_released': len(eip_results['released']),
                'snapshots_tagged': len(snapshot_results['tagged']),
                'untagged_instances': len(untagged_resources['instances']),
                'underutilized_instances': len(underutilized_instances)
            })
        }
        
    except Exception as e:
        logger.error(f"Cost optimization failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }


# For local testing
if __name__ == '__main__':
    # Set environment variables for local testing
    os.environ['DRY_RUN'] = 'true'
    os.environ['MIN_DAYS_BEFORE_DELETE'] = '7'
    
    lambda_handler({}, {})
