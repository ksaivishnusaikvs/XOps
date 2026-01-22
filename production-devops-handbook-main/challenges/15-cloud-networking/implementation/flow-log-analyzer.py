#!/usr/bin/env python3
"""
VPC Flow Logs Analyzer
Analyzes AWS VPC Flow Logs to detect security issues and anomalies
"""

import boto3
import json
from datetime import datetime, timedelta
from collections import defaultdict, Counter

class FlowLogAnalyzer:
    def __init__(self, log_group_name='/aws/vpc/production-flow-logs'):
        self.logs = boto3.client('logs')
        self.ec2 = boto3.client('ec2')
        self.log_group = log_group_name
        
    def query_flow_logs(self, hours=24):
        """Query flow logs using CloudWatch Logs Insights"""
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=hours)
        
        # Query for rejected connections
        query = """
        fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, protocol, action, bytes
        | filter action = "REJECT"
        | stats count() as rejections by srcAddr, dstAddr, dstPort
        | sort rejections desc
        | limit 100
        """
        
        response = self.logs.start_query(
            logGroupName=self.log_group,
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = response['queryId']
        
        # Wait for query to complete
        import time
        while True:
            result = self.logs.get_query_results(queryId=query_id)
            if result['status'] == 'Complete':
                return result['results']
            time.sleep(1)
    
    def detect_port_scanning(self, hours=1):
        """Detect potential port scanning activity"""
        query = """
        fields srcAddr, dstPort, action
        | filter action = "REJECT"
        | stats count_distinct(dstPort) as unique_ports by srcAddr
        | filter unique_ports > 20
        | sort unique_ports desc
        """
        
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=hours)
        
        response = self.logs.start_query(
            logGroupName=self.log_group,
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = response['queryId']
        
        import time
        while True:
            result = self.logs.get_query_results(queryId=query_id)
            if result['status'] == 'Complete':
                return result['results']
            time.sleep(1)
    
    def detect_data_exfiltration(self, threshold_gb=10):
        """Detect unusual outbound data transfer"""
        query = f"""
        fields srcAddr, dstAddr, sum(bytes) as total_bytes
        | filter action = "ACCEPT"
        | stats sum(bytes) as total_bytes by srcAddr
        | filter total_bytes > {threshold_gb * 1024 * 1024 * 1024}
        | sort total_bytes desc
        """
        
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=24)
        
        response = self.logs.start_query(
            logGroupName=self.log_group,
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = response['queryId']
        
        import time
        while True:
            result = self.logs.get_query_results(queryId=query_id)
            if result['status'] == 'Complete':
                return result['results']
            time.sleep(1)
    
    def analyze_security_group_denials(self):
        """Analyze which security groups are denying traffic"""
        rejected_logs = self.query_flow_logs(hours=1)
        
        denials = defaultdict(int)
        top_sources = Counter()
        top_destinations = Counter()
        
        for log_entry in rejected_logs:
            fields = {item['field']: item['value'] for item in log_entry}
            
            src = fields.get('srcAddr', 'unknown')
            dst = fields.get('dstAddr', 'unknown')
            port = fields.get('dstPort', 'unknown')
            count = int(fields.get('rejections', 0))
            
            denials[f"{dst}:{port}"] += count
            top_sources[src] += count
            top_destinations[dst] += count
        
        return {
            'total_denials': sum(denials.values()),
            'top_denied_endpoints': dict(sorted(denials.items(), key=lambda x: x[1], reverse=True)[:10]),
            'top_sources': dict(top_sources.most_common(10)),
            'top_destinations': dict(top_destinations.most_common(10))
        }
    
    def generate_report(self):
        """Generate comprehensive security analysis report"""
        print("\n" + "="*70)
        print("VPC FLOW LOGS SECURITY ANALYSIS")
        print("="*70)
        
        # Port scanning detection
        print("\n🔍 Port Scanning Detection...")
        port_scans = self.detect_port_scanning()
        if port_scans:
            print(f"⚠️  {len(port_scans)} potential port scanning attempts detected:")
            for scan in port_scans[:5]:
                fields = {item['field']: item['value'] for item in scan}
                print(f"   Source: {fields.get('srcAddr')} - {fields.get('unique_ports')} unique ports")
        else:
            print("✅ No port scanning detected")
        
        # Data exfiltration detection
        print("\n📤 Data Exfiltration Detection (>10GB outbound)...")
        exfil = self.detect_data_exfiltration()
        if exfil:
            print(f"⚠️  {len(exfil)} instances of high outbound traffic:")
            for instance in exfil[:5]:
                fields = {item['field']: item['value'] for item in instance}
                bytes_gb = int(fields.get('total_bytes', 0)) / (1024**3)
                print(f"   Source: {fields.get('srcAddr')} - {bytes_gb:.2f}GB")
        else:
            print("✅ No unusual outbound traffic detected")
        
        # Security group denials
        print("\n🚫 Security Group Denials Analysis...")
        sg_analysis = self.analyze_security_group_denials()
        print(f"Total Rejections (24h): {sg_analysis['total_denials']}")
        
        print("\nTop Denied Endpoints:")
        for endpoint, count in list(sg_analysis['top_denied_endpoints'].items())[:5]:
            print(f"   {endpoint}: {count} rejections")
        
        print("\nTop Source IPs:")
        for ip, count in list(sg_analysis['top_sources'].items())[:5]:
            print(f"   {ip}: {count} attempts")
        
        # Recommendations
        print("\n📋 RECOMMENDATIONS")
        print("="*70)
        
        if port_scans:
            print("❗ Block port scanning IPs in NACL/WAF")
        
        if exfil:
            print("❗ Investigate high outbound traffic instances")
        
        if sg_analysis['total_denials'] > 10000:
            print("❗ High denial rate - review security group rules")
        
        print("\n" + "="*70 + "\n")
        
        # Save report
        report = {
            'timestamp': datetime.now().isoformat(),
            'port_scans': len(port_scans) if port_scans else 0,
            'data_exfiltration': len(exfil) if exfil else 0,
            'security_group_analysis': sg_analysis
        }
        
        with open('flow_log_analysis.json', 'w') as f:
            json.dump(report, f, indent=2)
        
        return report

def main():
    analyzer = FlowLogAnalyzer()
    analyzer.generate_report()

if __name__ == '__main__':
    main()
