#!/bin/bash
#
# Kubernetes Secrets Management with External Secrets Operator
# Integrates with HashiCorp Vault, AWS Secrets Manager, Azure Key Vault
#
# Usage: ./secrets-management.sh [vault|aws|azure]
#

set -euo pipefail

PROVIDER="${1:-vault}"
NAMESPACE="default"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log "Setting up External Secrets Operator with $PROVIDER..."

# Install External Secrets Operator
log "Installing External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets \
    external-secrets/external-secrets \
    -n external-secrets-system \
    --create-namespace \
    --wait

log "✓ External Secrets Operator installed"

# Configure based on provider
case "$PROVIDER" in
    vault)
        log "Configuring HashiCorp Vault SecretStore..."
        kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: ${NAMESPACE}
spec:
  provider:
    vault:
      server: "http://vault.vault:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "demo"
          serviceAccountRef:
            name: "default"
EOF
        ;;
    
    aws)
        log "Configuring AWS Secrets Manager SecretStore..."
        kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: ${NAMESPACE}
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: "external-secrets-sa"
EOF
        ;;
    
    azure)
        log "Configuring Azure Key Vault SecretStore..."
        kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: azure-keyvault
  namespace: ${NAMESPACE}
spec:
  provider:
    azurekv:
      vaultUrl: "https://my-vault.vault.azure.net"
      authType: WorkloadIdentity
      serviceAccountRef:
        name: "external-secrets-sa"
EOF
        ;;
esac

log "Creating example ExternalSecret..."
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
  namespace: ${NAMESPACE}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: $([ "$PROVIDER" = "vault" ] && echo "vault-backend" || [ "$PROVIDER" = "aws" ] && echo "aws-secrets-manager" || echo "azure-keyvault")
    kind: SecretStore
  target:
    name: app-secrets
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: app/database
        property: password
    - secretKey: api-key
      remoteRef:
        key: app/api
        property: key
EOF

log "✓ Secrets management configured"

cat <<EOF

========================================
Secrets Management Setup Complete
========================================

Provider: $PROVIDER
SecretStore: Created in namespace $NAMESPACE
ExternalSecret: app-secrets

The ExternalSecret will sync secrets from $PROVIDER
to Kubernetes secrets every 1 hour.

Usage in Pod:
  env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: app-secrets
          key: database-password

========================================
EOF
