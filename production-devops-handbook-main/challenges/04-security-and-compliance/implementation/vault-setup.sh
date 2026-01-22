#!/bin/bash
#
# HashiCorp Vault Setup and Configuration
# Sets up Vault for secrets management in Kubernetes
#
# Usage: ./vault-setup.sh
#

set -euo pipefail

VAULT_NAMESPACE="vault"
VAULT_RELEASE="vault"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log "Setting up HashiCorp Vault on Kubernetes..."

# Add Vault Helm repository
log "Adding Vault Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Create namespace
kubectl create namespace "$VAULT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install Vault with Helm
log "Installing Vault..."
helm upgrade --install "$VAULT_RELEASE" hashicorp/vault \
    --namespace "$VAULT_NAMESPACE" \
    --set "server.ha.enabled=true" \
    --set "server.ha.replicas=3" \
    --set "ui.enabled=true" \
    --set "injector.enabled=true" \
    --wait

log "Waiting for Vault pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=vault \
    -n "$VAULT_NAMESPACE" \
    --timeout=300s

# Initialize Vault
log "Initializing Vault..."
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json > vault-keys.json

log "✓ Vault keys saved to vault-keys.json (KEEP THIS SECURE!)"

# Extract unseal keys and root token
UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' vault-keys.json)
UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' vault-keys.json)
UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' vault-keys.json)
ROOT_TOKEN=$(jq -r '.root_token' vault-keys.json)

# Unseal all Vault pods
for pod in vault-0 vault-1 vault-2; do
    log "Unsealing $pod..."
    kubectl exec -n "$VAULT_NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY_1"
    kubectl exec -n "$VAULT_NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY_2"
    kubectl exec -n "$VAULT_NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY_3"
done

log "✓ Vault unsealed successfully"

# Login with root token
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- vault login "$ROOT_TOKEN"

# Enable KV secrets engine
log "Enabling KV secrets engine..."
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- vault secrets enable -path=secret kv-v2

# Create example secret
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- vault kv put secret/myapp/config \
    database_url="postgresql://localhost:5432/myapp" \
    api_key="example-api-key"

log "✓ Example secret created at secret/myapp/config"

# Enable Kubernetes auth
log "Enabling Kubernetes authentication..."
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- vault auth enable kubernetes

# Configure Kubernetes auth
log "Configuring Kubernetes auth..."
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- sh -c '
vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
'

# Create policy for myapp
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- sh -c 'cat <<EOF | vault policy write myapp -
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}
EOF'

# Create Kubernetes role
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- vault write auth/kubernetes/role/myapp \
    bound_service_account_names=myapp \
    bound_service_account_namespaces=production \
    policies=myapp \
    ttl=24h

log "✓ Vault setup complete!"

cat <<EOF

========================================
Vault Configuration Summary
========================================

Vault URL: http://vault.${VAULT_NAMESPACE}.svc.cluster.local:8200
UI URL: kubectl port-forward -n ${VAULT_NAMESPACE} svc/vault-ui 8200:8200

Root Token: $ROOT_TOKEN
Unseal Keys: See vault-keys.json (KEEP SECURE!)

Next Steps:
1. Move unseal keys to secure storage
2. Set up auto-unseal with cloud KMS
3. Create application-specific policies
4. Inject secrets into pods using Vault Agent

Example Pod Annotation for Secret Injection:
---
metadata:
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "myapp"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"

========================================
EOF
