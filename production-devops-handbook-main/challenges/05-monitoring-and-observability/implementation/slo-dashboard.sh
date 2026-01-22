#!/bin/bash
#
# SLO/SLI Dashboard Setup Script
# Creates Service Level Objectives and Indicators dashboards
#
# Usage: ./slo-dashboard.sh
#

set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

NAMESPACE="observability"
SERVICE_NAME="${1:-myapp}"

log "Creating SLO Dashboard for $SERVICE_NAME..."

# Create Grafana dashboard for SLOs
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: slo-dashboard-${SERVICE_NAME}
  namespace: ${NAMESPACE}
  labels:
    grafana_dashboard: "1"
data:
  slo-dashboard.json: |
    {
      "dashboard": {
        "title": "${SERVICE_NAME} SLO Dashboard",
        "tags": ["slo", "sli", "${SERVICE_NAME}"],
        "panels": [
          {
            "id": 1,
            "title": "Availability SLO (99.9%)",
            "type": "gauge",
            "targets": [
              {
                "expr": "avg_over_time((sum(rate(http_requests_total{service='${SERVICE_NAME}',status!~'5..'}[5m])) / sum(rate(http_requests_total{service='${SERVICE_NAME}'}[5m])))[30d:]) * 100"
              }
            ],
            "thresholds": "99.9,99.95",
            "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0}
          },
          {
            "id": 2,
            "title": "Latency SLO (p95 < 200ms)",
            "type": "gauge",
            "targets": [
              {
                "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{service='${SERVICE_NAME}'}[5m])) * 1000"
              }
            ],
            "thresholds": "200,300",
            "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0}
          },
          {
            "id": 3,
            "title": "Error Budget Remaining",
            "type": "stat",
            "targets": [
              {
                "expr": "((1 - 0.999) - (1 - avg_over_time((sum(rate(http_requests_total{service='${SERVICE_NAME}',status!~'5..'}[5m])) / sum(rate(http_requests_total{service='${SERVICE_NAME}'}[5m])))[30d:]))) / (1 - 0.999) * 100"
              }
            ],
            "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0}
          }
        ]
      }
    }
EOF

log "✓ SLO Dashboard created for $SERVICE_NAME"

cat <<EOF

========================================
SLO Metrics Configured:
- Availability: 99.9% uptime
- Latency: p95 < 200ms
- Error Budget tracking

Access Dashboard:
  kubectl port-forward -n ${NAMESPACE} svc/prometheus-grafana 3000:80

========================================
EOF
