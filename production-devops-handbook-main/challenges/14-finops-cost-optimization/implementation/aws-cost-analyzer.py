#!/usr/bin/env python3
"""
AWS Cost Analyzer - Comprehensive Cloud Cost Analysis Tool
Analyzes AWS costs across services, regions, and tags
"""

import boto3
import json
from datetime import datetime, timedelta
from collections import defaultdict
import argparse

class AWSCostAnalyzer:
    def __init__(self, profile=None):
        session = boto3.Session(profile_name=profile) if profile else boto3.Session()
        self.ce_client = session.client('ce')
        self.cloudwatch = session.client('cloudwatch')
        
    def get_cost_and_usage(self, start_date, end_date, granularity='DAILY', metrics=['UnblendedCost']):
        """Get cost and usage data from Cost Explorer"""
        response = self.ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity=granularity,
            Metrics=metrics,
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
            ]
        )
        return response['ResultsByTime']
    
    def get_cost_by_tag(self, start_date, end_date, tag_key):
        """Analyze costs by specific tag"""
        try:
            response = self.ce_client.get_cost_and_usage(
                TimePeriod={
                    'Start': start_date.strftime('%Y-%m-%d'),
                    'End': end_date.strftime('%Y-%m-%d')
                },
                Granularity='MONTHLY',
                Metrics=['UnblendedCost'],
                GroupBy=[
                    {'Type': 'TAG', 'Key': tag_key}
                ]
            )
            return response['ResultsByTime']
        except Exception as e:
            print(f"Error analyzing costs by tag {tag_key}: {e}")
            return []
    
    def get_untagged_resources_cost(self, start_date, end_date):
        """Find costs from untagged resources"""
        response = self.ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['UnblendedCost'],
            Filter={
                'Not': {
                    'Tags': {
                        'Key': 'Environment',
                        'Values': ['*']
                    }
                }
            }
        )
        return response['ResultsByTime']
    
    def detect_cost_anomalies(self, start_date, end_date, threshold_percentage=20):
        """Detect cost anomalies"""
        results = self.get_cost_and_usage(start_date, end_date, 'DAILY')
        
        anomalies = []
        previous_cost = None
        
        for result in results:
            current_cost = float(result['Total']['UnblendedCost']['Amount'])
            
            if previous_cost:
                change_percentage = ((current_cost - previous_cost) / previous_cost) * 100
                
                if abs(change_percentage) > threshold_percentage:
                    anomalies.append({
                        'date': result['TimePeriod']['Start'],
                        'current_cost': current_cost,
                        'previous_cost': previous_cost,
                        'change_percentage': change_percentage,
                        'severity': 'HIGH' if abs(change_percentage) > 50 else 'MEDIUM'
                    })
            
            previous_cost = current_cost
        
        return anomalies
    
    def get_top_cost_services(self, start_date, end_date, top_n=10):
        """Get top N services by cost"""
        results = self.get_cost_and_usage(start_date, end_date, 'MONTHLY')
        
        service_costs = defaultdict(float)
        
        for result in results:
            for group in result.get('Groups', []):
                service = group['Keys'][0]
                cost = float(group['Metrics']['UnblendedCost']['Amount'])
                service_costs[service] += cost
        
        sorted_services = sorted(service_costs.items(), key=lambda x: x[1], reverse=True)
        return sorted_services[:top_n]
    
    def get_ri_coverage(self):
        """Get Reserved Instance coverage"""
        end_date = datetime.now()
        start_date = end_date - timedelta(days=30)
        
        response = self.ce_client.get_reservation_coverage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY'
        )
        
        coverage_data = []
        for period in response['CoveragesByTime']:
            coverage = period['Total']
            coverage_data.append({
                'period': period['TimePeriod']['Start'],
                'coverage_percentage': coverage.get('CoverageHours', {}).get('CoverageHoursPercentage', '0'),
                'on_demand_cost': coverage.get('CoverageCost', {}).get('OnDemandCost', '0')
            })
        
        return coverage_data
    
    def get_savings_plan_coverage(self):
        """Get Savings Plans coverage"""
        end_date = datetime.now()
        start_date = end_date - timedelta(days=30)
        
        response = self.ce_client.get_savings_plans_coverage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY'
        )
        
        coverage_data = []
        for period in response['SavingsPlansCoverages']:
            coverage = period['Coverage']
            coverage_data.append({
                'period': period['TimePeriod']['Start'],
                'coverage_percentage': coverage.get('CoveragePercentage', '0'),
                'spend_covered': coverage.get('SpendCoveredBySavingsPlans', '0')
            })
        
        return coverage_data
    
    def generate_report(self, output_file='cost_analysis_report.json'):
        """Generate comprehensive cost analysis report"""
        end_date = datetime.now()
        start_date = end_date - timedelta(days=30)
        
        report = {
            'generated_at': datetime.now().isoformat(),
            'period': {
                'start': start_date.strftime('%Y-%m-%d'),
                'end': end_date.strftime('%Y-%m-%d')
            },
            'analysis': {}
        }
        
        # Total costs
        print("Analyzing total costs...")
        cost_data = self.get_cost_and_usage(start_date, end_date, 'MONTHLY')
        total_cost = sum(float(result['Total']['UnblendedCost']['Amount']) for result in cost_data)
        report['analysis']['total_cost'] = round(total_cost, 2)
        
        # Top services
        print("Analyzing top cost services...")
        top_services = self.get_top_cost_services(start_date, end_date)
        report['analysis']['top_services'] = [
            {'service': service, 'cost': round(cost, 2)}
            for service, cost in top_services
        ]
        
        # Cost anomalies
        print("Detecting cost anomalies...")
        anomalies = self.detect_cost_anomalies(start_date, end_date)
        report['analysis']['anomalies'] = anomalies
        
        # RI Coverage
        print("Analyzing Reserved Instance coverage...")
        ri_coverage = self.get_ri_coverage()
        report['analysis']['ri_coverage'] = ri_coverage
        
        # Savings Plans Coverage
        print("Analyzing Savings Plans coverage...")
        sp_coverage = self.get_savings_plan_coverage()
        report['analysis']['savings_plans_coverage'] = sp_coverage
        
        # Cost by environment tag
        print("Analyzing costs by environment...")
        env_costs = self.get_cost_by_tag(start_date, end_date, 'Environment')
        report['analysis']['cost_by_environment'] = env_costs
        
        # Untagged resources
        print("Analyzing untagged resources...")
        untagged_costs = self.get_untagged_resources_cost(start_date, end_date)
        untagged_total = sum(float(r['Total']['UnblendedCost']['Amount']) for r in untagged_costs)
        report['analysis']['untagged_resources_cost'] = round(untagged_total, 2)
        report['analysis']['untagged_percentage'] = round((untagged_total / total_cost) * 100, 2) if total_cost > 0 else 0
        
        # Recommendations
        report['recommendations'] = self._generate_recommendations(report['analysis'])
        
        # Save report
        with open(output_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"\n✅ Report generated: {output_file}")
        return report
    
    def _generate_recommendations(self, analysis):
        """Generate cost optimization recommendations"""
        recommendations = []
        
        # RI coverage recommendation
        if analysis.get('ri_coverage'):
            avg_coverage = sum(float(c['coverage_percentage']) for c in analysis['ri_coverage']) / len(analysis['ri_coverage'])
            if avg_coverage < 70:
                recommendations.append({
                    'category': 'Reserved Instances',
                    'priority': 'HIGH',
                    'recommendation': f'RI coverage is {avg_coverage:.1f}%, target is 70%+. Consider purchasing RIs for steady-state workloads.',
                    'potential_savings': 'Up to 40% on covered instances'
                })
        
        # Untagged resources
        if analysis.get('untagged_percentage', 0) > 20:
            recommendations.append({
                'category': 'Resource Tagging',
                'priority': 'HIGH',
                'recommendation': f'{analysis["untagged_percentage"]:.1f}% of costs are untagged. Implement tagging strategy for cost allocation.',
                'impact': 'Improved visibility and accountability'
            })
        
        # Cost anomalies
        if analysis.get('anomalies'):
            high_anomalies = [a for a in analysis['anomalies'] if a['severity'] == 'HIGH']
            if high_anomalies:
                recommendations.append({
                    'category': 'Cost Anomalies',
                    'priority': 'CRITICAL',
                    'recommendation': f'Detected {len(high_anomalies)} high-severity cost anomalies. Investigate immediately.',
                    'action': 'Review anomaly dates and associated services'
                })
        
        return recommendations
    
    def print_summary(self, report):
        """Print human-readable summary"""
        print("\n" + "="*60)
        print("AWS COST ANALYSIS SUMMARY")
        print("="*60)
        
        print(f"\n📊 Period: {report['period']['start']} to {report['period']['end']}")
        print(f"💰 Total Cost: ${report['analysis']['total_cost']:,.2f}")
        
        print("\n🔝 Top 5 Services by Cost:")
        for i, service in enumerate(report['analysis']['top_services'][:5], 1):
            print(f"  {i}. {service['service']}: ${service['cost']:,.2f}")
        
        print(f"\n🏷️  Untagged Resources: ${report['analysis']['untagged_resources_cost']:,.2f} ({report['analysis']['untagged_percentage']:.1f}%)")
        
        if report['analysis'].get('anomalies'):
            print(f"\n⚠️  Cost Anomalies Detected: {len(report['analysis']['anomalies'])}")
        
        if report.get('recommendations'):
            print(f"\n💡 Recommendations ({len(report['recommendations'])}):")
            for rec in report['recommendations']:
                print(f"  [{rec['priority']}] {rec['category']}: {rec['recommendation']}")
        
        print("\n" + "="*60 + "\n")

def main():
    parser = argparse.ArgumentParser(description='AWS Cost Analysis Tool')
    parser.add_argument('--profile', help='AWS profile name')
    parser.add_argument('--output', default='cost_analysis_report.json', help='Output file path')
    
    args = parser.parse_args()
    
    analyzer = AWSCostAnalyzer(profile=args.profile)
    report = analyzer.generate_report(output_file=args.output)
    analyzer.print_summary(report)

if __name__ == '__main__':
    main()
