# Monitoring and Observability - Complete Implementation Guide

## Step 1: Deploy Prometheus Stack

### 1.1 Install Prometheus Operator
```bash
# Add Prometheus community helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --set grafana.adminPassword=admin123 \
  --set alertmanager.enabled=true
```

### 1.2 Access Grafana
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000
# Login: admin / admin123
```

## Step 2: Configure Application Metrics

### 2.1 Add Prometheus Client Library

**Node.js (Express)**
```javascript
const express = require('express');
const promClient = require('prom-client');

const app = express();

// Create metrics registry
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

// Custom metrics
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5]
});

const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestsTotal);

// Middleware to track metrics
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.route?.path || req.path, res.statusCode).observe(duration);
    httpRequestsTotal.labels(req.method, req.route?.path || req.path, res.statusCode).inc();
  });
  
  next();
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.listen(8080, () => console.log('Server running on port 8080'));
```

**Python (Flask)**
```python
from flask import Flask, request
from prometheus_client import Counter, Histogram, generate_latest, REGISTRY
import time

app = Flask(__name__)

# Metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status_code']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint'],
    buckets=[0.01, 0.05, 0.1, 0.5, 1, 2, 5]
)

@app.before_request
def before_request():
    request.start_time = time.time()

@app.after_request
def after_request(response):
    request_latency = time.time() - request.start_time
    REQUEST_LATENCY.labels(request.method, request.path).observe(request_latency)
    REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    return response

@app.route('/metrics')
def metrics():
    return generate_latest(REGISTRY)

@app.route('/health')
def health():
    return {'status': 'healthy'}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

### 2.2 Configure Pod Annotations
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
spec:
  containers:
  - name: myapp
    image: myapp:latest
    ports:
    - containerPort: 8080
      name: http-metrics
```

## Step 3: Set Up Distributed Tracing

### 3.1 Deploy Jaeger
```bash
# Deploy Jaeger operator
kubectl create namespace observability
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.50.0/jaeger-operator.yaml -n observability

# Create Jaeger instance
kubectl apply -f - <<EOF
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: jaeger
  namespace: observability
spec:
  strategy: production
  storage:
    type: elasticsearch
    options:
      es:
        server-urls: http://elasticsearch:9200
EOF
```

### 3.2 Instrument Application (OpenTelemetry)

**Node.js**
```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { JaegerExporter } = require('@opentelemetry/exporter-jaeger');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'myapp',
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
  }),
  traceExporter: new JaegerExporter({
    endpoint: 'http://jaeger-collector:14268/api/traces',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
```

**Python**
```python
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.flask import FlaskInstrumentor

# Configure tracer
resource = Resource(attributes={
    "service.name": "myapp",
    "service.version": "1.0.0"
})

jaeger_exporter = JaegerExporter(
    agent_host_name="jaeger-agent",
    agent_port=6831,
)

provider = TracerProvider(resource=resource)
processor = BatchSpanProcessor(jaeger_exporter)
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)

# Auto-instrument Flask
FlaskInstrumentor().instrument_app(app)
```

## Step 4: Centralized Logging with Loki

### 4.1 Deploy Loki Stack
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false \
  --set prometheus.enabled=false \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=10Gi
```

### 4.2 Configure Promtail
```yaml
# promtail-config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: app
      - source_labels: [__meta_kubernetes_pod_label_version]
        target_label: version
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
    pipeline_stages:
      - docker: {}
      - json:
          expressions:
            level: level
            message: message
            timestamp: timestamp
      - labels:
          level:
      - timestamp:
          source: timestamp
          format: RFC3339Nano
```

### 4.3 Structured Logging in Application

**Node.js (Winston)**
```javascript
const winston = require('winston');

const logger = winston.createLogger({
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console()
  ]
});

// Usage
logger.info('User logged in', { userId: 123, email: 'user@example.com' });
logger.error('Database connection failed', { error: err.message });
```

**Python (structlog)**
```python
import structlog

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.PrintLoggerFactory(),
)

logger = structlog.get_logger()

# Usage
logger.info("user_logged_in", user_id=123, email="user@example.com")
logger.error("database_connection_failed", error=str(e))
```

## Step 5: Create Grafana Dashboards

### 5.1 Import Pre-built Dashboards
```bash
# Access Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Import these dashboard IDs:
# - 315: Kubernetes cluster monitoring
# - 3119: Kubernetes pod resources
# - 6417: Kubernetes deployment
# - 7249: Kubernetes cluster overview
```

### 5.2 Create Custom Dashboard (JSON)
```json
{
  "dashboard": {
    "title": "Application Performance",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[5m])) by (service)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (service)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "95th Percentile Latency",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))"
          }
        ],
        "type": "graph"
      }
    ]
  }
}
```

## Step 6: Configure Alertmanager

### 6.1 Alertmanager Configuration
```yaml
# alertmanager-config.yaml
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
      continue: true
    - match:
        severity: warning
      receiver: 'slack'

receivers:
  - name: 'default'
    slack_configs:
      - channel: '#alerts'
        title: 'Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'slack'
    slack_configs:
      - channel: '#warnings'
        send_resolved: true
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ .Annotations.description }}{{ end }}'

  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_KEY'
        description: '{{ .GroupLabels.alertname }}: {{ .Annotations.summary }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster', 'service']
```

## Step 7: Implement SLO/SLI Monitoring

### 7.1 Define SLIs
```yaml
# sli-recording-rules.yml
groups:
  - name: sli_recording_rules
    interval: 30s
    rules:
      # Availability SLI
      - record: sli:availability:ratio_rate5m
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[5m]))
          /
          sum(rate(http_requests_total[5m]))

      # Latency SLI (95th percentile < 500ms)
      - record: sli:latency:ratio_rate5m
        expr: |
          sum(rate(http_request_duration_seconds_bucket{le="0.5"}[5m]))
          /
          sum(rate(http_request_duration_seconds_count[5m]))

      # Error budget burn rate
      - record: slo:error_budget_burn_rate:1h
        expr: |
          1 - sli:availability:ratio_rate5m
```

### 7.2 Create SLO Alerts
```yaml
groups:
  - name: slo_alerts
    rules:
      - alert: SLOBurnRateTooHigh
        expr: |
          (
            slo:error_budget_burn_rate:1h > (14.4 * (1 - 0.999))
          and
            slo:error_budget_burn_rate:5m > (14.4 * (1 - 0.999))
          )
        labels:
          severity: critical
        annotations:
          summary: "Error budget is burning too fast"
          description: "At current rate, monthly error budget will be exhausted in less than 2 days"
```

## Step 8: Set Up Synthetic Monitoring

### 8.1 Deploy Blackbox Exporter
```bash
helm install prometheus-blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  --namespace monitoring
```

### 8.2 Configure Probes
```yaml
# blackbox-config.yaml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      method: GET
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      fail_if_ssl: false
      fail_if_not_ssl: true
      
  http_post_2xx:
    prober: http
    http:
      method: POST
      headers:
        Content-Type: application/json
      body: '{"test": "data"}'
```

### 8.3 Add Prometheus Scrape Config
```yaml
- job_name: 'blackbox'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
        - https://example.com
        - https://api.example.com/health
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: prometheus-blackbox-exporter:9115
```

## Step 9: Implement Cost Monitoring

### 9.1 Deploy Kubecost
```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="YOUR_TOKEN"
```

### 9.2 Track Resource Costs
```promql
# Cost per namespace
sum(container_memory_working_set_bytes) by (namespace) * on (namespace) group_left() 
  label_replace(
    kube_namespace_labels{label_cost_center!=""},
    "namespace",
    "$1",
    "namespace",
    "(.*)"
  )
```

## Step 10: Create Runbooks

### 10.1 Runbook Template
```markdown
# High Error Rate Runbook

## Alert
**Name:** HighErrorRate  
**Severity:** Critical  
**SLO Impact:** Yes (affects availability SLO)

## Symptoms
- Error rate > 5% for 5+ minutes
- Users experiencing 5xx errors
- Customer complaints about service availability

## Investigation Steps
1. Check Grafana dashboard for error patterns
2. Review application logs in Loki
3. Check distributed traces in Jaeger
4. Verify database connectivity
5. Check external service dependencies

## Resolution Steps
1. If database issue: Restart connection pool
2. If deployment issue: Rollback to previous version
3. If external service: Enable circuit breaker
4. If traffic spike: Scale up pods

## Prevention
- Implement better error handling
- Add circuit breakers
- Improve test coverage
- Set up canary deployments
```

## Observability Checklist

- [ ] Metrics collection (Prometheus)
- [ ] Centralized logging (Loki)
- [ ] Distributed tracing (Jaeger)
- [ ] Dashboards (Grafana)
- [ ] Alerting (Alertmanager)
- [ ] SLO/SLI monitoring
- [ ] Synthetic monitoring
- [ ] Cost monitoring
- [ ] Runbooks documented
- [ ] On-call rotation defined
