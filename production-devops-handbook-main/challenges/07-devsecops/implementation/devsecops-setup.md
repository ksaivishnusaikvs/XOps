# DevSecOps Implementation - Step-by-Step Guide

## Step 1: Install Security Scanning Tools

### 1.1 Install Core Security Tools
```bash
# Trivy (Container & IaC scanning)
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install trivy

# Grype (Vulnerability scanner)
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh

# Gitleaks (Secret detection)
brew install gitleaks
# or
wget https://github.com/zricethezav/gitleaks/releases/download/v8.18.0/gitleaks_8.18.0_linux_x64.tar.gz
tar -xzf gitleaks_8.18.0_linux_x64.tar.gz
sudo mv gitleaks /usr/local/bin/

# Semgrep (SAST)
pip install semgrep

# Checkov (IaC security)
pip install checkov

# Hadolint (Dockerfile linter)
docker pull hadolint/hadolint

# Snyk
npm install -g snyk
snyk auth
```

### 1.2 Install Language-Specific Tools
```bash
# Python
pip install bandit safety pip-licenses

# Node.js
npm install -g npm-audit-resolver license-checker

# Go
go install github.com/securego/gosec/v2/cmd/gosec@latest
```

## Step 2: Configure Pre-Commit Hooks

### 2.1 Install pre-commit
```bash
pip install pre-commit
```

### 2.2 Create .pre-commit-config.yaml
```yaml
repos:
  # Secret Detection
  - repo: https://github.com/zricethezav/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
  
  # Detect Private Keys
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: detect-private-key
      - id: detect-aws-credentials
        args: ['--allow-missing-credentials']
      - id: check-added-large-files
        args: ['--maxkb=1000']
      - id: check-merge-conflict
      - id: check-yaml
      - id: end-of-file-fixer
      - id: trailing-whitespace
  
  # Terraform Security
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.83.5
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tfsec
        args:
          - --args=--minimum-severity=MEDIUM
      - id: terraform_checkov
  
  # Dockerfile Linting
  - repo: https://github.com/hadolint/hadolint
    rev: v2.12.0
    hooks:
      - id: hadolint-docker
  
  # Python Security
  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.5
    hooks:
      - id: bandit
        args: ['-c', 'pyproject.toml']
  
  # YAML Linting
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.33.0
    hooks:
      - id: yamllint
```

### 2.3 Initialize and Test
```bash
pre-commit install
pre-commit run --all-files
```

## Step 3: Integrate Security into CI/CD

### 3.1 GitHub Actions Workflow
```yaml
name: DevSecOps Pipeline

on: [push, pull_request]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for better secret detection
      
      # Secret Scanning
      - name: Gitleaks Secret Scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      
      # SAST
      - name: Run Semgrep
        uses: returntocorp/semgrep-action@v1
        with:
          config: >-
            p/security-audit
            p/secrets
            p/owasp-top-ten
      
      # Dependency Scanning
      - name: Run Snyk Security Scan
        uses: snyk/actions/node@master
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        with:
          args: --severity-threshold=high
      
      # Container Scanning
      - name: Build Docker Image
        run: docker build -t myapp:${{ github.sha }} .
      
      - name: Run Trivy Vulnerability Scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'myapp:${{ github.sha }}'
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'
      
      - name: Upload Trivy Results to GitHub Security
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'
      
      # IaC Security
      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          framework: terraform,dockerfile,kubernetes
          output_format: sarif
          output_file_path: checkov.sarif
          soft_fail: false
      
      - name: Upload Checkov to GitHub Security
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: checkov.sarif
      
      # Generate Security Report
      - name: Generate Security Report
        run: |
          echo "# Security Scan Results" > security-report.md
          echo "**Date:** $(date)" >> security-report.md
          echo "**Commit:** ${{ github.sha }}" >> security-report.md
      
      - name: Upload Security Report
        uses: actions/upload-artifact@v3
        with:
          name: security-reports
          path: |
            trivy-results.sarif
            checkov.sarif
            security-report.md
```

## Step 4: Implement Runtime Security

### 4.1 Deploy Falco for Runtime Monitoring
```bash
# Add Falco Helm repository
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# Install Falco
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=ebpf \
  --set tty=true
```

### 4.2 Create Custom Falco Rules
```yaml
# custom-rules.yaml
- rule: Unauthorized Process in Container
  desc: Detect unauthorized process execution in containers
  condition: >
    spawned_process and
    container and
    not proc.name in (allowed_processes) and
    not container.image.repository in (trusted_images)
  output: >
    Unauthorized process started in container
    (user=%user.name command=%proc.cmdline container=%container.name 
    image=%container.image.repository)
  priority: WARNING
  tags: [process, container]

- rule: Write to System Directory
  desc: Detect writes to system directories
  condition: >
    open_write and
    container and
    fd.name startswith /bin or
    fd.name startswith /sbin or
    fd.name startswith /usr/bin or
    fd.name startswith /usr/sbin
  output: >
    File write to system directory
    (user=%user.name file=%fd.name container=%container.name)
  priority: ERROR
  tags: [filesystem, container]

- rule: Reverse Shell
  desc: Detect potential reverse shell
  condition: >
    spawned_process and
    container and
    ((proc.name in (bash, sh, zsh) and
    proc.args contains "-i") or
    (proc.name in (nc, ncat, netcat) and
    (proc.args contains "-e" or proc.args contains "-c")))
  output: >
    Potential reverse shell detected
    (user=%user.name command=%proc.cmdline container=%container.name)
  priority: CRITICAL
  tags: [network, container, shell]
```

### 4.3 Apply Custom Rules
```bash
kubectl create configmap falco-rules \
  --from-file=custom-rules.yaml \
  -n falco

kubectl patch daemonset falco \
  -n falco \
  -p '{"spec":{"template":{"spec":{"volumes":[{"name":"falco-rules","configMap":{"name":"falco-rules"}}]}}}}'
```

## Step 5: Implement Network Security

### 5.1 Create Network Policies
```yaml
# default-deny-all.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
# allow-dns.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
---
# allow-app-to-db.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - protocol: TCP
      port: 5432
```

## Step 6: Secrets Management with Vault

### 6.1 Deploy HashiCorp Vault
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.dev.enabled=false" \
  --set "server.ha.enabled=true" \
  --set "server.ha.replicas=3"
```

### 6.2 Initialize and Unseal Vault
```bash
kubectl exec vault-0 -n vault -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > cluster-keys.json

# Unseal vault (repeat for each replica)
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)
kubectl exec vault-0 -n vault -- vault operator unseal $VAULT_UNSEAL_KEY
```

### 6.3 Configure Vault for Kubernetes
```bash
kubectl exec vault-0 -n vault -- vault auth enable kubernetes

kubectl exec vault-0 -n vault -- vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

# Create policy
kubectl exec vault-0 -n vault -- vault policy write myapp - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

# Create role
kubectl exec vault-0 -n vault -- vault write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp \
  bound_service_account_namespaces=production \
  policies=myapp \
  ttl=24h
```

### 6.4 Use Vault in Applications
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "myapp"
        vault.hashicorp.com/agent-inject-secret-database: "secret/data/myapp/database"
        vault.hashicorp.com/agent-inject-template-database: |
          {{- with secret "secret/data/myapp/database" -}}
          export DB_HOST="{{ .Data.data.host }}"
          export DB_USER="{{ .Data.data.username }}"
          export DB_PASS="{{ .Data.data.password }}"
          {{- end }}
    spec:
      serviceAccountName: myapp
      containers:
      - name: app
        image: myapp:latest
        command: ["/bin/sh", "-c"]
        args:
          - source /vault/secrets/database && ./start-app.sh
```

## Step 7: Implement Security Scanning in Development

### 7.1 IDE Integration (VS Code)
```json
// .vscode/settings.json
{
  "semgrep.scan.configuration": "auto",
  "semgrep.scan.enable": true,
  "snyk.token": "${SNYK_TOKEN}",
  "gitleaks.enable": true
}
```

### 7.2 Add npm Scripts for Security
```json
// package.json
{
  "scripts": {
    "security:check": "npm audit && snyk test",
    "security:fix": "npm audit fix && snyk wizard",
    "security:scan": "semgrep --config=auto .",
    "security:secrets": "gitleaks detect --source=."
  }
}
```

## Step 8: Compliance and Reporting

### 8.1 Generate Compliance Report
```bash
#!/bin/bash
# compliance-report.sh

cat > compliance-report.md <<EOF
# Security Compliance Report
**Date:** $(date)

## CIS Kubernetes Benchmark
$(kubectl get nodes -o json | jq -r '.items[] | .metadata.name')

## Pod Security Standards
- Enforced: $(kubectl get ns -o json | jq -r '.items[] | select(.metadata.labels["pod-security.kubernetes.io/enforce"]) | .metadata.name')

## Network Policies
$(kubectl get networkpolicies --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers | wc -l) policies configured

## Secret Management
- Sealed Secrets: $(kubectl get sealedsecrets --all-namespaces --no-headers | wc -l)
- External Secrets: $(kubectl get externalsecrets --all-namespaces --no-headers | wc -l)

## Security Scanning
- Last Container Scan: $(date)
- Critical Vulnerabilities: 0
- High Vulnerabilities: 2
EOF
```

## DevSecOps Checklist

- [ ] Secret scanning in git (Gitleaks)
- [ ] Pre-commit hooks configured
- [ ] SAST integrated (Semgrep)
- [ ] Dependency scanning (Snyk, npm audit)
- [ ] Container scanning (Trivy, Grype)
- [ ] IaC security scanning (Checkov, tfsec)
- [ ] Runtime security monitoring (Falco)
- [ ] Network policies enforced
- [ ] Secrets management (Vault)
- [ ] Security gates in CI/CD
- [ ] Compliance reporting automated
- [ ] Security training completed
