#!/bin/bash
#
# Backstage Internal Developer Platform Setup
# Deploys Backstage with service catalog and templates
#
# Usage: ./backstage-setup.sh
#

set -euo pipefail

NAMESPACE="backstage"
APP_NAME="backstage"

GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log "Setting up Backstage Internal Developer Platform..."

# Create namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create PostgreSQL for Backstage
log "Deploying PostgreSQL database..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secrets
  namespace: $NAMESPACE
type: Opaque
stringData:
  POSTGRES_USER: backstage
  POSTGRES_PASSWORD: backstage
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: $NAMESPACE
spec:
  ports:
    - port: 5432
  selector:
    app: postgres
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15-alpine
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: postgres-secrets
          volumeMounts:
            - name: postgres-storage
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: postgres-storage
          emptyDir: {}
EOF

# Wait for PostgreSQL
log "Waiting for PostgreSQL..."
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=120s

# Deploy Backstage
log "Deploying Backstage..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: backstage-app-config
  namespace: $NAMESPACE
data:
  app-config.yaml: |
    app:
      title: Developer Portal
      baseUrl: http://localhost:3000

    organization:
      name: My Company

    backend:
      baseUrl: http://localhost:7007
      listen:
        port: 7007
      database:
        client: pg
        connection:
          host: postgres
          port: 5432
          user: backstage
          password: backstage

    catalog:
      locations:
        - type: url
          target: https://github.com/backstage/backstage/blob/master/packages/catalog-model/examples/all.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
        - name: backstage
          image: backstage/backstage:latest
          ports:
            - containerPort: 7007
            - containerPort: 3000
          env:
            - name: POSTGRES_HOST
              value: postgres
            - name: POSTGRES_PORT
              value: "5432"
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-secrets
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secrets
                  key: POSTGRES_PASSWORD
          volumeMounts:
            - name: app-config
              mountPath: /app/app-config.yaml
              subPath: app-config.yaml
      volumes:
        - name: app-config
          configMap:
            name: backstage-app-config
---
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
spec:
  type: LoadBalancer
  ports:
    - name: http
      port: 80
      targetPort: 3000
    - name: backend
      port: 7007
      targetPort: 7007
  selector:
    app: $APP_NAME
EOF

log "✓ Backstage deployed successfully!"

cat <<EOF

========================================
Backstage Platform Access
========================================

Access Backstage:
  kubectl port-forward -n $NAMESPACE svc/$APP_NAME 3000:80
  URL: http://localhost:3000

Next Steps:
1. Add service catalogs
2. Create software templates
3. Configure integrations (GitHub, GitLab, etc.)
4. Set up TechDocs for documentation

========================================
EOF
