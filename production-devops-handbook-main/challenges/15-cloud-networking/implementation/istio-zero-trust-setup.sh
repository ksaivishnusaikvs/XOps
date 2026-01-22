#!/bin/bash
# Install Istio Service Mesh for Zero-Trust Networking
# Provides automatic mutual TLS between services

set -euo pipefail

ISTIO_VERSION="1.20.1"
NAMESPACE="istio-system"

echo "🚀 Installing Istio ${ISTIO_VERSION} for Zero-Trust Networking..."

# Download Istio
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
cd istio-${ISTIO_VERSION}

# Install Istio with strict mTLS mode
./bin/istioctl install -y --set profile=production \
  --set values.global.proxy.privileged=true \
  --set meshConfig.accessLogFile=/dev/stdout \
  --set meshConfig.enableTracing=true

# Enable strict mTLS for entire mesh
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF

# Authorization policy - deny all by default
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: istio-system
spec:
  {}
EOF

# Enable automatic sidecar injection for production namespace
kubectl label namespace production istio-injection=enabled --overwrite

# Deploy Istio Gateway
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: production-gateway
  namespace: production
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: production-tls-cert
    hosts:
    - "*.example.com"
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*.example.com"
    tls:
      httpsRedirect: true
EOF

# Authorization policy for frontend service
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: frontend-authz
  namespace: production
spec:
  selector:
    matchLabels:
      app: frontend
  action: ALLOW
  rules:
  - from:
    - source:
        namespaces: ["istio-system"]
    to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/*"]
EOF

# Authorization policy for API service
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-authz
  namespace: production
spec:
  selector:
    matchLabels:
      app: api
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/production/sa/frontend"]
    to:
    - operation:
        methods: ["GET", "POST", "PUT", "DELETE"]
        paths: ["/api/*"]
EOF

# Authorization policy for database - only allow API service
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: database-authz
  namespace: production
spec:
  selector:
    matchLabels:
      app: postgres
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/production/sa/api"]
    to:
    - operation:
        ports: ["5432"]
EOF

# Deploy Kiali (service mesh observability)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

# Deploy Jaeger (distributed tracing)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml

# Verify installation
echo "✅ Waiting for Istio components to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/istiod -n istio-system

echo "
✅ Istio installation complete!

Zero-Trust Features Enabled:
- ✅ Strict mutual TLS for all services
- ✅ Service-to-service authorization policies
- ✅ Automatic sidecar injection
- ✅ Distributed tracing
- ✅ Service mesh observability (Kiali)

Verify mTLS:
  istioctl authn tls-check <pod-name> -n production

Access Kiali dashboard:
  kubectl port-forward -n istio-system svc/kiali 20001:20001
  Open: http://localhost:20001

Access Jaeger tracing:
  kubectl port-forward -n istio-system svc/tracing 16686:80
  Open: http://localhost:16686
"
