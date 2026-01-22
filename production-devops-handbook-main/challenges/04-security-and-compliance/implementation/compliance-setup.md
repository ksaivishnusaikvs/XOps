# Security and Compliance - Step-by-Step Implementation

## Step 1: Set Up Security Scanning Tools

### 1.1 Install Trivy (Container Scanning)
```bash
# Linux
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy

# macOS
brew install trivy

# Windows
choco install trivy
```

### 1.2 Install Security Scanning Tools
```bash
# Install Checkov (IaC Security)
pip install checkov

# Install TruffleHog (Secret Scanning)
pip install trufflehog

# Install Semgrep (SAST)
pip install semgrep

# Install Safety (Python Dependencies)
pip install safety

# Install npm audit (Node.js - built-in)
npm install -g npm@latest
```

## Step 2: Integrate Security in CI/CD Pipeline

### 2.1 Add to GitHub Actions
```yaml
name: Security Scan

on: [push, pull_request]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-results.sarif'
      
      - name: Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'
      
      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          framework: terraform,kubernetes,dockerfile
          output_format: sarif
          output_file_path: checkov-results.sarif
      
      - name: Run Semgrep
        uses: returntocorp/semgrep-action@v1
        with:
          config: auto
      
      - name: Secret Scanning
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: main
```

## Step 3: Implement Pre-Commit Security Hooks

### 3.1 Create .pre-commit-config.yaml
```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: detect-aws-credentials
      - id: detect-private-key
      - id: check-added-large-files
        args: ['--maxkb=1000']
  
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
  
  - repo: https://github.com/bridgecrewio/checkov
    rev: 3.0.0
    hooks:
      - id: checkov
        args: [--quiet, --framework, terraform, kubernetes]
```

### 3.2 Install and Run
```bash
pre-commit install
pre-commit run --all-files
```

## Step 4: Implement Secrets Management

### 4.1 Set Up HashiCorp Vault
```bash
# Start Vault in dev mode (for testing)
vault server -dev

# In another terminal
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='your-dev-token'

# Enable secrets engine
vault secrets enable -path=secret kv-v2

# Store a secret
vault kv put secret/myapp/db password="supersecret" username="dbuser"

# Retrieve a secret
vault kv get secret/myapp/db
```

### 4.2 Use Vault in Applications
```python
# Python example
import hvac

client = hvac.Client(url='http://127.0.0.1:8200')
client.token = 'your-token'

secret = client.secrets.kv.v2.read_secret_version(path='myapp/db')
db_password = secret['data']['data']['password']
```

```javascript
// Node.js example
const vault = require('node-vault')();

async function getSecret() {
  const secret = await vault.read('secret/data/myapp/db');
  return secret.data.data.password;
}
```

### 4.3 Kubernetes Integration
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp
  namespace: myapp
---
apiVersion: v1
kind: Secret
metadata:
  name: myapp-vault-token
  namespace: myapp
type: Opaque
data:
  token: <base64-encoded-vault-token>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      serviceAccountName: myapp
      initContainers:
      - name: vault-init
        image: vault:latest
        command:
          - sh
          - -c
          - |
            vault kv get -field=password secret/myapp/db > /secrets/db-password
        volumeMounts:
        - name: secrets
          mountPath: /secrets
      containers:
      - name: app
        image: myapp:latest
        volumeMounts:
        - name: secrets
          mountPath: /secrets
          readOnly: true
      volumes:
      - name: secrets
        emptyDir:
          medium: Memory
```

## Step 5: Implement RBAC and Pod Security

### 5.1 Create Service Account with Limited Permissions
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  namespace: myapp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: myapp-role
  namespace: myapp
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: myapp-rolebinding
  namespace: myapp
subjects:
- kind: ServiceAccount
  name: myapp-sa
roleRef:
  kind: Role
  name: myapp-role
  apiGroup: rbac.authorization.k8s.io
```

### 5.2 Implement Pod Security Standards
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 5.3 Security Context Best Practices
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:latest
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
```

## Step 6: Implement Network Security

### 6.1 Create Network Policies
```yaml
# Deny all ingress by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: myapp
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
# Allow specific ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: myapp
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### 6.2 Use Service Mesh (Istio)
```bash
# Install Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
istioctl install --set profile=default -y

# Enable sidecar injection
kubectl label namespace myapp istio-injection=enabled
```

## Step 7: Implement Compliance Monitoring

### 7.1 Install Falco (Runtime Security)
```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set tty=true
```

### 7.2 Configure Custom Falco Rules
```yaml
# custom-rules.yaml
- rule: Unauthorized Process
  desc: Detect unauthorized process in container
  condition: >
    spawned_process and
    container and
    not proc.name in (allowed_processes)
  output: >
    Unauthorized process started
    (user=%user.name command=%proc.cmdline container=%container.name)
  priority: WARNING

- rule: Write to Non-Temp Directory
  desc: Detect writes to non-temporary directories
  condition: >
    open_write and
    container and
    not fd.name startswith /tmp
  output: >
    File write to non-temp directory
    (user=%user.name file=%fd.name container=%container.name)
  priority: WARNING
```

## Step 8: Continuous Compliance Monitoring

### 8.1 Set Up Compliance Dashboard
```bash
# Install Kubernetes Dashboard with security metrics
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard \
  --create-namespace
```

### 8.2 Automated Compliance Reports
```bash
#!/bin/bash
# compliance-report.sh

# Generate compliance report
{
  echo "# Compliance Report - $(date)"
  echo ""
  echo "## Pod Security"
  kubectl get pods --all-namespaces -o json | \
    jq -r '.items[] | select(.spec.securityContext.runAsNonRoot != true) | .metadata.name'
  
  echo ""
  echo "## Network Policies"
  kubectl get networkpolicies --all-namespaces
  
  echo ""
  echo "## RBAC Review"
  kubectl get clusterrolebindings -o json | \
    jq -r '.items[] | select(.subjects[]?.kind == "ServiceAccount" and .subjects[]?.name == "default")'
  
} > compliance-report-$(date +%Y%m%d).md
```

## Step 9: Implement Image Signing

### 9.1 Set Up Cosign
```bash
# Install cosign
brew install cosign  # macOS
# or download from https://github.com/sigstore/cosign

# Generate key pair
cosign generate-key-pair

# Sign image
cosign sign --key cosign.key myregistry/myapp:v1.0.0
```

### 9.2 Verify Signatures with Policy Controller
```bash
# Install policy controller
kubectl apply -f https://github.com/sigstore/policy-controller/releases/latest/download/policy-controller.yaml
```

```yaml
# Create verification policy
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: image-verification-policy
spec:
  images:
  - glob: "myregistry/myapp:*"
  authorities:
  - key:
      data: |
        -----BEGIN PUBLIC KEY-----
        <your-public-key>
        -----END PUBLIC KEY-----
```

## Step 10: Security Audit and Remediation

### 10.1 Regular Security Audits
```bash
# Weekly security audit script
#!/bin/bash

# 1. Scan all container images
trivy image --severity HIGH,CRITICAL $(kubectl get pods --all-namespaces -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u)

# 2. Check for outdated images
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | {name: .metadata.name, image: .spec.containers[].image}'

# 3. Review RBAC permissions
kubectl auth can-i --list --as=system:serviceaccount:default:default

# 4. Check secrets encryption at rest
kubectl get secrets --all-namespaces -o json | \
  jq -r '.items[] | select(.type == "Opaque") | .metadata.name'
```

## Compliance Checklist

### CIS Kubernetes Benchmark
- [ ] Use RBAC for authorization
- [ ] Encrypt secrets at rest
- [ ] Enable audit logging
- [ ] Use Network Policies
- [ ] Implement Pod Security Standards
- [ ] Regular security updates
- [ ] Limit container capabilities
- [ ] Use read-only root filesystems
- [ ] Implement resource quotas
- [ ] Enable API server authentication

### SOC 2 / PCI DSS
- [ ] Implement encryption in transit (TLS)
- [ ] Implement encryption at rest
- [ ] Access control and authentication
- [ ] Audit logging and monitoring
- [ ] Regular security assessments
- [ ] Incident response plan
- [ ] Data retention policies
- [ ] Backup and recovery procedures
