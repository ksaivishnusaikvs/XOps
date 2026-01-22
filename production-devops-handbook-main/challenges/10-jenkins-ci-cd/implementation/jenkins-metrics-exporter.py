#!/usr/bin/env python3
"""
Jenkins Build Metrics Exporter for Prometheus
Collects and exposes Jenkins build metrics for monitoring and alerting
"""

import os
import time
import requests
from datetime import datetime, timedelta
from prometheus_client import CollectorRegistry, Gauge, Counter, Histogram, push_to_gateway
from prometheus_client.exposition import basic_auth_handler

# ============================================================================
# Configuration
# ============================================================================

JENKINS_URL = os.getenv('JENKINS_URL', 'https://jenkins.company.com')
JENKINS_USER = os.getenv('JENKINS_USER', 'metrics-user')
JENKINS_TOKEN = os.getenv('JENKINS_API_TOKEN')
PUSHGATEWAY_URL = os.getenv('PUSHGATEWAY_URL', 'pushgateway.monitoring:9091')
SCRAPE_INTERVAL = int(os.getenv('SCRAPE_INTERVAL', '60'))  # seconds

# ============================================================================
# Prometheus Metrics
# ============================================================================

registry = CollectorRegistry()

# Build metrics
jenkins_builds_total = Counter(
    'jenkins_builds_total',
    'Total number of Jenkins builds',
    ['job', 'result'],
    registry=registry
)

jenkins_build_duration_seconds = Histogram(
    'jenkins_build_duration_seconds',
    'Jenkins build duration in seconds',
    ['job'],
    buckets=[30, 60, 120, 300, 600, 1200, 1800, 3600],
    registry=registry
)

jenkins_build_queue_size = Gauge(
    'jenkins_build_queue_size',
    'Number of builds in Jenkins queue',
    registry=registry
)

jenkins_executor_total = Gauge(
    'jenkins_executor_total',
    'Total number of Jenkins executors',
    registry=registry
)

jenkins_executor_busy = Gauge(
    'jenkins_executor_busy',
    'Number of busy Jenkins executors',
    registry=registry
)

jenkins_job_last_build_timestamp = Gauge(
    'jenkins_job_last_build_timestamp',
    'Timestamp of last build for job',
    ['job'],
    registry=registry
)

jenkins_job_last_success_timestamp = Gauge(
    'jenkins_job_last_success_timestamp',
    'Timestamp of last successful build for job',
    ['job'],
    registry=registry
)

jenkins_job_health_score = Gauge(
    'jenkins_job_health_score',
    'Health score of Jenkins job (0-100)',
    ['job'],
    registry=registry
)

jenkins_plugin_total = Gauge(
    'jenkins_plugin_total',
    'Total number of Jenkins plugins',
    ['status'],
    registry=registry
)

jenkins_node_total = Gauge(
    'jenkins_node_total',
    'Total number of Jenkins nodes',
    ['status'],
    registry=registry
)

# ============================================================================
# Jenkins API Client
# ============================================================================

class JenkinsClient:
    def __init__(self, url, user, token):
        self.url = url.rstrip('/')
        self.auth = (user, token)
        self.session = requests.Session()
        self.session.auth = self.auth
    
    def get(self, endpoint):
        """Make GET request to Jenkins API"""
        try:
            response = self.session.get(
                f"{self.url}/{endpoint}",
                timeout=30
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"Error fetching {endpoint}: {e}")
            return None
    
    def get_queue(self):
        """Get build queue information"""
        return self.get('queue/api/json')
    
    def get_computer(self):
        """Get executor/node information"""
        return self.get('computer/api/json')
    
    def get_all_jobs(self):
        """Get all jobs recursively"""
        data = self.get('api/json?tree=jobs[name,url,buildable,color,healthReport]')
        if not data:
            return []
        
        jobs = []
        for job in data.get('jobs', []):
            if job.get('buildable'):
                jobs.append(job)
        
        return jobs
    
    def get_job_details(self, job_name):
        """Get detailed information about a job"""
        return self.get(f"job/{job_name}/api/json")
    
    def get_last_builds(self, job_name, count=10):
        """Get last N builds for a job"""
        data = self.get(
            f"job/{job_name}/api/json?tree=builds[number,result,duration,timestamp]{{,{count}}}"
        )
        if not data:
            return []
        
        return data.get('builds', [])
    
    def get_plugins(self):
        """Get installed plugins"""
        return self.get('pluginManager/api/json?depth=1')

# ============================================================================
# Metrics Collection
# ============================================================================

def collect_queue_metrics(client):
    """Collect build queue metrics"""
    queue_data = client.get_queue()
    if not queue_data:
        return
    
    queue_size = len(queue_data.get('items', []))
    jenkins_build_queue_size.set(queue_size)
    print(f"Queue size: {queue_size}")

def collect_executor_metrics(client):
    """Collect executor/node metrics"""
    computer_data = client.get_computer()
    if not computer_data:
        return
    
    total_executors = 0
    busy_executors = 0
    online_nodes = 0
    offline_nodes = 0
    
    for computer in computer_data.get('computer', []):
        if computer.get('offline'):
            offline_nodes += 1
        else:
            online_nodes += 1
        
        num_executors = computer.get('numExecutors', 0)
        total_executors += num_executors
        
        # Count busy executors
        for executor in computer.get('executors', []):
            if executor.get('currentExecutable'):
                busy_executors += 1
    
    jenkins_executor_total.set(total_executors)
    jenkins_executor_busy.set(busy_executors)
    jenkins_node_total.labels(status='online').set(online_nodes)
    jenkins_node_total.labels(status='offline').set(offline_nodes)
    
    print(f"Executors: {busy_executors}/{total_executors} busy")
    print(f"Nodes: {online_nodes} online, {offline_nodes} offline")

def collect_job_metrics(client):
    """Collect metrics for all jobs"""
    jobs = client.get_all_jobs()
    print(f"Collecting metrics for {len(jobs)} jobs")
    
    for job in jobs:
        job_name = job['name']
        
        try:
            # Get job details
            job_details = client.get_job_details(job_name)
            if not job_details:
                continue
            
            # Last build timestamp
            last_build = job_details.get('lastBuild')
            if last_build:
                timestamp = last_build.get('timestamp', 0) / 1000
                jenkins_job_last_build_timestamp.labels(job=job_name).set(timestamp)
            
            # Last successful build timestamp
            last_success = job_details.get('lastSuccessfulBuild')
            if last_success:
                timestamp = last_success.get('timestamp', 0) / 1000
                jenkins_job_last_success_timestamp.labels(job=job_name).set(timestamp)
            
            # Health score
            health_report = job.get('healthReport', [])
            if health_report:
                health_score = health_report[0].get('score', 0)
                jenkins_job_health_score.labels(job=job_name).set(health_score)
            
            # Recent builds
            builds = client.get_last_builds(job_name, count=10)
            
            for build in builds:
                result = build.get('result', 'UNKNOWN')
                duration = build.get('duration', 0) / 1000  # Convert to seconds
                
                # Count builds by result
                jenkins_builds_total.labels(
                    job=job_name,
                    result=result
                ).inc(0)  # Initialize counter
                
                # Record duration
                if duration > 0:
                    jenkins_build_duration_seconds.labels(job=job_name).observe(duration)
            
            print(f"  ✓ {job_name}: {len(builds)} builds")
            
        except Exception as e:
            print(f"  ✗ {job_name}: {e}")

def collect_plugin_metrics(client):
    """Collect plugin metrics"""
    plugin_data = client.get_plugins()
    if not plugin_data:
        return
    
    plugins = plugin_data.get('plugins', [])
    
    active_plugins = sum(1 for p in plugins if p.get('active'))
    enabled_plugins = sum(1 for p in plugins if p.get('enabled'))
    
    jenkins_plugin_total.labels(status='active').set(active_plugins)
    jenkins_plugin_total.labels(status='enabled').set(enabled_plugins)
    jenkins_plugin_total.labels(status='total').set(len(plugins))
    
    print(f"Plugins: {active_plugins} active, {enabled_plugins} enabled, {len(plugins)} total")

def collect_all_metrics(client):
    """Collect all metrics"""
    print(f"\n{'='*60}")
    print(f"Collecting metrics at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*60}")
    
    collect_queue_metrics(client)
    collect_executor_metrics(client)
    collect_plugin_metrics(client)
    collect_job_metrics(client)
    
    print(f"{'='*60}\n")

def push_metrics():
    """Push metrics to Prometheus Pushgateway"""
    try:
        push_to_gateway(
            PUSHGATEWAY_URL,
            job='jenkins-metrics-exporter',
            registry=registry
        )
        print("Metrics pushed to Pushgateway")
    except Exception as e:
        print(f"Error pushing metrics: {e}")

# ============================================================================
# Main Loop
# ============================================================================

def main():
    """Main execution loop"""
    if not JENKINS_TOKEN:
        print("ERROR: JENKINS_API_TOKEN environment variable not set")
        return
    
    print(f"Jenkins Metrics Exporter")
    print(f"Jenkins URL: {JENKINS_URL}")
    print(f"Pushgateway: {PUSHGATEWAY_URL}")
    print(f"Scrape Interval: {SCRAPE_INTERVAL}s")
    print()
    
    client = JenkinsClient(JENKINS_URL, JENKINS_USER, JENKINS_TOKEN)
    
    while True:
        try:
            collect_all_metrics(client)
            push_metrics()
        except KeyboardInterrupt:
            print("\nShutting down...")
            break
        except Exception as e:
            print(f"Error in main loop: {e}")
        
        time.sleep(SCRAPE_INTERVAL)

if __name__ == '__main__':
    main()
