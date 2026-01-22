#!/usr/bin/env python3
"""
AWS Right-Sizing Recommendations
Analyzes EC2 and RDS instances for rightsizing opportunities
"""

import boto3
import json
from datetime import datetime, timedelta
from collections import defaultdict

class RightSizingAnalyzer:
    def __init__(self):
        self.ec2 = boto3.client('ec2')
        self.rds = boto3.client('rds')
        self.cloudwatch = boto3.client('cloudwatch')
        self.pricing = boto3.client('pricing', region_name='us-east-1')
        
    def analyze_ec2_instances(self, days=14):
        """Analyze EC2 instances for rightsizing"""
        recommendations = []
        
        # Get all running instances
        response = self.ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
        )
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_type = instance['InstanceType']
                
                # Get CloudWatch metrics
                metrics = self.get_instance_metrics(instance_id, days)
                
                # Analyze utilization
                recommendation = self.generate_ec2_recommendation(
                    instance_id, instance_type, metrics
                )
                
                if recommendation:
                    recommendations.append(recommendation)
        
        return recommendations
    
    def get_instance_metrics(self, instance_id, days):
        """Get CloudWatch metrics for EC2 instance"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=days)
        
        metrics = {
            'cpu_utilization': self.get_metric_stats(
                instance_id, 'CPUUtilization', start_time, end_time, 'Average'
            ),
            'network_in': self.get_metric_stats(
                instance_id, 'NetworkIn', start_time, end_time, 'Average'
            ),
            'network_out': self.get_metric_stats(
                instance_id, 'NetworkOut', start_time, end_time, 'Average'
            )
        }
        
        return metrics
    
    def get_metric_stats(self, instance_id, metric_name, start_time, end_time, stat):
        """Get CloudWatch metric statistics"""
        try:
            response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName=metric_name,
                Dimensions=[
                    {'Name': 'InstanceId', 'Value': instance_id}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,  # 1 hour
                Statistics=[stat]
            )
            
            if response['Datapoints']:
                values = [dp[stat] for dp in response['Datapoints']]
                return {
                    'average': sum(values) / len(values),
                    'max': max(values),
                    'p95': sorted(values)[int(len(values) * 0.95)] if values else 0
                }
            return {'average': 0, 'max': 0, 'p95': 0}
        except Exception as e:
            print(f"Error getting metrics for {instance_id}: {e}")
            return {'average': 0, 'max': 0, 'p95': 0}
    
    def generate_ec2_recommendation(self, instance_id, instance_type, metrics):
        """Generate rightsizing recommendation"""
        cpu_avg = metrics['cpu_utilization']['average']
        cpu_p95 = metrics['cpu_utilization']['p95']
        
        recommendation = None
        
        # Over-provisioned (CPU < 10%)
        if cpu_avg < 10 and cpu_p95 < 20:
            recommendation = {
                'instance_id': instance_id,
                'current_type': instance_type,
                'action': 'DOWNSIZE',
                'suggested_type': self.suggest_smaller_instance(instance_type),
                'reason': f'Low CPU utilization (avg: {cpu_avg:.1f}%, p95: {cpu_p95:.1f}%)',
                'potential_savings': self.calculate_savings(instance_type, 'downsize'),
                'priority': 'HIGH' if cpu_avg < 5 else 'MEDIUM'
            }
        
        # Under-provisioned (CPU > 80%)
        elif cpu_avg > 80 or cpu_p95 > 90:
            recommendation = {
                'instance_id': instance_id,
                'current_type': instance_type,
                'action': 'UPSIZE',
                'suggested_type': self.suggest_larger_instance(instance_type),
                'reason': f'High CPU utilization (avg: {cpu_avg:.1f}%, p95: {cpu_p95:.1f}%)',
                'priority': 'HIGH',
                'risk': 'Performance degradation'
            }
        
        return recommendation
    
    def suggest_smaller_instance(self, instance_type):
        """Suggest a smaller instance type"""
        # Simplified logic - map to smaller instances
        size_map = {
            '2xlarge': 'xlarge',
            'xlarge': 'large',
            'large': 'medium',
            'medium': 'small'
        }
        
        for size, smaller in size_map.items():
            if size in instance_type:
                return instance_type.replace(size, smaller)
        
        return instance_type
    
    def suggest_larger_instance(self, instance_type):
        """Suggest a larger instance type"""
        size_map = {
            'small': 'medium',
            'medium': 'large',
            'large': 'xlarge',
            'xlarge': '2xlarge'
        }
        
        for size, larger in size_map.items():
            if size in instance_type:
                return instance_type.replace(size, larger)
        
        return instance_type
    
    def calculate_savings(self, instance_type, action):
        """Calculate potential monthly savings"""
        # Simplified pricing (real implementation would use AWS Pricing API)
        base_cost = 100  # Base monthly cost
        
        if action == 'downsize':
            return f"~${base_cost * 0.5:.2f}/month (50% savings)"
        
        return "N/A"
    
    def generate_report(self):
        """Generate comprehensive rightsizing report"""
        print("Analyzing EC2 instances...")
        ec2_recommendations = self.analyze_ec2_instances()
        
        report = {
            'generated_at': datetime.now().isoformat(),
            'ec2_recommendations': ec2_recommendations,
            'summary': {
                'total_analyzed': len(ec2_recommendations),
                'downsize_opportunities': len([r for r in ec2_recommendations if r.get('action') == 'DOWNSIZE']),
                'upsize_needed': len([r for r in ec2_recommendations if r.get('action') == 'UPSIZE']),
                'estimated_savings': self.calculate_total_savings(ec2_recommendations)
            }
        }
        
        # Save report
        with open('rightsizing_report.json', 'w') as f:
            json.dump(report, f, indent=2)
        
        self.print_summary(report)
        return report
    
    def calculate_total_savings(self, recommendations):
        """Calculate total potential savings"""
        # Simplified calculation
        downsize_count = len([r for r in recommendations if r.get('action') == 'DOWNSIZE'])
        return f"~${downsize_count * 50:.2f}/month"
    
    def print_summary(self, report):
        """Print human-readable summary"""
        print("\n" + "="*60)
        print("RIGHT-SIZING RECOMMENDATIONS SUMMARY")
        print("="*60)
        
        summary = report['summary']
        print(f"\n📊 Total Instances Analyzed: {summary['total_analyzed']}")
        print(f"⬇️  Downsize Opportunities: {summary['downsize_opportunities']}")
        print(f"⬆️  Upsize Needed: {summary['upsize_needed']}")
        print(f"💰 Estimated Monthly Savings: {summary['estimated_savings']}")
        
        if report['ec2_recommendations']:
            print("\n🔍 Top Recommendations:")
            for i, rec in enumerate(report['ec2_recommendations'][:5], 1):
                action_emoji = "⬇️" if rec['action'] == 'DOWNSIZE' else "⬆️"
                print(f"\n  {i}. {action_emoji} {rec['instance_id']}")
                print(f"     Current: {rec['current_type']} → Suggested: {rec.get('suggested_type', 'N/A')}")
                print(f"     Reason: {rec['reason']}")
                if rec.get('potential_savings'):
                    print(f"     Savings: {rec['potential_savings']}")
        
        print("\n" + "="*60 + "\n")

def main():
    analyzer = RightSizingAnalyzer()
    analyzer.generate_report()

if __name__ == '__main__':
    main()
