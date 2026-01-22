#!/usr/bin/env python3
"""
Automated Resource Cleanup Script
Identifies and removes unused AWS resources to reduce costs
"""

import boto3
from datetime import datetime, timedelta
import json

class ResourceCleanup:
    def __init__(self, dry_run=True):
        self.dry_run = dry_run
        self.ec2 = boto3.client('ec2')
        self.elb = boto3.client('elbv2')
        self.rds = boto3.client('rds')
        self.s3 = boto3.client('s3')
        self.cleanup_report = {
            'snapshots_deleted': [],
            'volumes_deleted': [],
            'eips_released': [],
            'load_balancers_deleted': [],
            'total_savings': 0
        }
    
    def cleanup_old_snapshots(self, days_old=90):
        """Delete snapshots older than specified days"""
        print(f"🔍 Finding snapshots older than {days_old} days...")
        
        snapshots = self.ec2.describe_snapshots(OwnerIds=['self'])['Snapshots']
        cutoff_date = datetime.now(snapshots[0]['StartTime'].tzinfo) - timedelta(days=days_old)
        
        old_snapshots = [s for s in snapshots if s['StartTime'] < cutoff_date]
        
        for snapshot in old_snapshots:
            snapshot_id = snapshot['SnapshotId']
            size_gb = snapshot['VolumeSize']
            
            if not self.dry_run:
                try:
                    self.ec2.delete_snapshot(SnapshotId=snapshot_id)
                    print(f"✅ Deleted snapshot: {snapshot_id} ({size_gb}GB)")
                except Exception as e:
                    print(f"❌ Failed to delete {snapshot_id}: {e}")
            else:
                print(f"[DRY RUN] Would delete: {snapshot_id} ({size_gb}GB)")
            
            self.cleanup_report['snapshots_deleted'].append({
                'id': snapshot_id,
                'size_gb': size_gb,
                'savings_per_month': size_gb * 0.05  # $0.05 per GB-month
            })
        
        return len(old_snapshots)
    
    def cleanup_unattached_volumes(self):
        """Delete unattached EBS volumes"""
        print("🔍 Finding unattached volumes...")
        
        volumes = self.ec2.describe_volumes(
            Filters=[{'Name': 'status', 'Values': ['available']}]
        )['Volumes']
        
        for volume in volumes:
            volume_id = volume['VolumeId']
            size_gb = volume['Size']
            volume_type = volume['VolumeType']
            
            if not self.dry_run:
                try:
                    self.ec2.delete_volume(VolumeId=volume_id)
                    print(f"✅ Deleted volume: {volume_id}")
                except Exception as e:
                    print(f"❌ Failed to delete {volume_id}: {e}")
            else:
                print(f"[DRY RUN] Would delete: {volume_id} ({size_gb}GB {volume_type})")
            
            self.cleanup_report['volumes_deleted'].append({
                'id': volume_id,
                'size_gb': size_gb,
                'type': volume_type
            })
        
        return len(volumes)
    
    def cleanup_unassociated_eips(self):
        """Release unassociated Elastic IPs"""
        print("🔍 Finding unassociated Elastic IPs...")
        
        eips = self.ec2.describe_addresses()['Addresses']
        unassociated = [eip for eip in eips if 'AssociationId' not in eip]
        
        for eip in unassociated:
            allocation_id = eip.get('AllocationId')
            public_ip = eip.get('PublicIp')
            
            if not self.dry_run and allocation_id:
                try:
                    self.ec2.release_address(AllocationId=allocation_id)
                    print(f"✅ Released EIP: {public_ip}")
                except Exception as e:
                    print(f"❌ Failed to release {public_ip}: {e}")
            else:
                print(f"[DRY RUN] Would release: {public_ip}")
            
            self.cleanup_report['eips_released'].append({
                'ip': public_ip,
                'savings_per_month': 3.60  # ~$0.005/hour
            })
        
        return len(unassociated)
    
    def run_cleanup(self):
        """Run all cleanup operations"""
        print("\n" + "="*60)
        print(f"RESOURCE CLEANUP {'(DRY RUN)' if self.dry_run else '(LIVE)'}")
        print("="*60 + "\n")
        
        snapshot_count = self.cleanup_old_snapshots()
        volume_count = self.cleanup_unattached_volumes()
        eip_count = self.cleanup_unassociated_eips()
        
        # Calculate total savings
        snapshot_savings = sum(s['savings_per_month'] for s in self.cleanup_report['snapshots_deleted'])
        eip_savings = len(self.cleanup_report['eips_released']) * 3.60
        
        self.cleanup_report['total_savings'] = snapshot_savings + eip_savings
        
        # Print summary
        print("\n" + "="*60)
        print("CLEANUP SUMMARY")
        print("="*60)
        print(f"\n📸 Snapshots: {snapshot_count}")
        print(f"💾 Volumes: {volume_count}")
        print(f"🌐 Elastic IPs: {eip_count}")
        print(f"💰 Estimated Monthly Savings: ${self.cleanup_report['total_savings']:.2f}")
        print("\n" + "="*60 + "\n")
        
        # Save report
        with open('cleanup_report.json', 'w') as f:
            json.dump(self.cleanup_report, f, indent=2)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute', action='store_true', help='Actually perform cleanup (default is dry-run)')
    args = parser.parse_args()
    
    cleanup = ResourceCleanup(dry_run=not args.execute)
    cleanup.run_cleanup()
