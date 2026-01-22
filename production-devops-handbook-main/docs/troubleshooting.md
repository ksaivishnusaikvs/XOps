# Troubleshooting Guide for DevOps Challenges

This comprehensive troubleshooting guide covers common issues across all 9 challenges with specific solutions and debugging steps. Each section references the actual implementation files in the repository.

## Table of Contents
- [General Troubleshooting Workflow](#general-troubleshooting-workflow)
- [Challenge 01: Infrastructure as Code](#challenge-01-infrastructure-as-code)
- [Challenge 02: CI/CD Pipeline Optimization](#challenge-02-cicd-pipeline-optimization)
- [Challenge 03: Kubernetes Complexity](#challenge-03-kubernetes-complexity)
- [Challenge 04: Security and Compliance](#challenge-04-security-and-compliance)
- [Challenge 05: Monitoring and Observability](#challenge-05-monitoring-and-observability)
- [Challenge 06: Platform Engineering](#challenge-06-platform-engineering)
- [Challenge 07: DevSecOps](#challenge-07-devsecops)
- [Challenge 08: AI/ML/LLM Ops](#challenge-08-aiml-llm-ops)
- [Challenge 09: Linux System Administration](#challenge-09-linux-system-administration)

---

## General Troubleshooting Workflow

### 1. Identify the Problem
- Collect error messages and stack traces
- Check logs from all relevant components
- Determine if the issue is reproducible
- Identify when the issue started

### 2. Gather Context
```bash
# System information
kubectl version --client
terraform --version
docker --version

# Check resource availability
kubectl top nodes
kubectl top pods

# Review recent changes
git log --oneline -n 10
```

### 3. Isolate the Issue
- Test in isolation (local, dev, staging)
- Verify configuration against working examples
- Check for recent changes or deployments

### 4. Check Documentation
- Review the relevant challenge's `problem.md` and `solution.md`
- Check tool documentation
- Search GitHub issues for similar problems

### 5. Consult the Community
- Stack Overflow with specific error messages
- Tool-specific Slack channels or forums
- GitHub issues for the tool

---

## Challenge 01: Infrastructure as Code

### Issue: Terraform State Lock Error
**Error**: `Error: Error acquiring the state lock`

**Cause**: Previous operation crashed or didn't release lock

**Solution**:
```bash
# Check DynamoDB for locks
aws dynamodb scan --table-name terraform-state-locks

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

**Prevention**: Use the remote state setup from `remote-state-setup.sh`

---

### Issue: Terraform Drift Detected
**Error**: `Warning: Resource drift detected`

**Cause**: Manual changes made outside Terraform

**Solution**:
```bash
# Run drift detection
./challenges/01-infrastructure-as-code/implementation/drift-detection.sh

# Review changes
terraform plan -refresh-only

# Import existing resources
terraform import <resource_type>.<name> <resource_id>

# Or recreate to match state
terraform apply -auto-approve
```

**Reference**: See `drift-detection.sh` for automated detection

---

### Issue: Pre-commit Hooks Failing
**Error**: `terraform validate failed` or `checkov failed`

**Cause**: Invalid Terraform syntax or security issues

**Solution**:
```bash
# Check what's failing
pre-commit run --all-files

# Fix formatting
terraform fmt -recursive

# Address security issues
checkov -d . --framework terraform

# Update hooks
pre-commit autoupdate
```

**Reference**: See `pre-commit-setup.sh` for configuration

---

### Issue: Module Not Found
**Error**: `Error: Module not found`

**Cause**: Module source path incorrect or not initialized

**Solution**:
```bash
# Re-initialize
terraform init -upgrade

# Check module source
cat main.tf | grep "source ="

# For local modules, verify path
ls -la ./modules/
```

---

## Challenge 02: CI/CD Pipeline Optimization

### Issue: Docker Build Extremely Slow
**Symptoms**: Build takes 10+ minutes for simple changes

**Solution**:
```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1

# Run optimization script
./challenges/02-ci-cd-pipeline-optimization/implementation/docker-optimization.sh

# Check layer caching
docker build --progress=plain .

# Use multi-stage build
# See Dockerfile.optimized for example
```

**Key Points**:
- Copy package files before source code
- Use `.dockerignore` to exclude unnecessary files
- Leverage build cache

---

### Issue: GitHub Actions Workflow Failing
**Error**: Various CI/CD errors

**Debugging**:
```bash
# Check workflow syntax
cat .github/workflows/ci.yml | grep -A 5 "jobs:"

# Review logs in GitHub Actions UI
# Look for specific step failures

# Test locally with act
act -n  # dry run
act     # full run
```

**Common Fixes**:
- Check secrets are configured: Settings → Secrets and variables → Actions
- Verify permissions: Add `permissions:` block
- Check cache keys match between save and restore

**Reference**: See `advanced-caching.yml` for best practices

---

### Issue: Docker Image Too Large
**Symptoms**: Image size > 1GB

**Solution**:
```bash
# Analyze layers
docker history myimage:latest

# Use dive for detailed analysis
dive myimage:latest

# Switch to minimal base image
# Alpine or distroless
FROM node:18-alpine  # Instead of node:18

# Multi-stage build
# See Dockerfile.optimized
```

---

### Issue: Dependency Caching Not Working
**Symptoms**: Dependencies re-downloaded every build

**Solution**:
```yaml
# In GitHub Actions workflow
- uses: actions/cache@v3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-npm-
```

**Reference**: See `advanced-caching.yml`

---

## Challenge 03: Kubernetes Complexity

### Issue: Pods Not Starting
**Error**: `CrashLoopBackOff`, `ImagePullBackOff`, or `Pending`

**Debugging**:
```bash
# Check pod status
kubectl get pods -n <namespace>

# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container

# Common causes:
# 1. Image pull errors
kubectl describe pod <pod> | grep -A 5 "Events:"

# 2. Resource constraints
kubectl describe nodes | grep -A 5 "Allocated resources"

# 3. Configuration errors
kubectl get configmap -n <namespace>
kubectl get secret -n <namespace>
```

**Solutions**:
- **ImagePullBackOff**: Check image name, tag, and registry credentials
- **CrashLoopBackOff**: Check logs, environment variables, and health checks
- **Pending**: Check resource requests vs node capacity

**Reference**: Use `k8s-deploy.sh` for safe deployments with validation

---

### Issue: Service Not Reachable
**Symptoms**: Cannot access service via ClusterIP or LoadBalancer

**Debugging**:
```bash
# Check service
kubectl get svc -n <namespace>

# Verify endpoints
kubectl get endpoints -n <namespace>

# Test from within cluster
kubectl run test --rm -it --image=busybox -- sh
wget -O- http://service-name:port

# Check NetworkPolicies
kubectl get networkpolicies -n <namespace>
```

**Solutions**:
- Verify selector labels match pod labels
- Check NetworkPolicy isn't blocking traffic
- For LoadBalancer, verify cloud provider integration

**Reference**: See `network-policies.yaml` for zero-trust networking

---

### Issue: HPA Not Scaling
**Error**: HPA shows `<unknown>` for metrics

**Debugging**:
```bash
# Check HPA status
kubectl get hpa -n <namespace>

# Describe for details
kubectl describe hpa <hpa-name> -n <namespace>

# Verify metrics-server
kubectl get deployment metrics-server -n kube-system

# Check metrics
kubectl top pods -n <namespace>
```

**Solution**:
```bash
# Install metrics-server if missing
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Ensure resource requests are set
# Pods must have CPU/memory requests for HPA
```

**Reference**: See `production-deployment.yaml` for HPA configuration

---

### Issue: Deployment Rollout Stuck
**Symptoms**: Rollout doesn't complete

**Debugging**:
```bash
# Check rollout status
kubectl rollout status deployment/<name> -n <namespace>

# View rollout history
kubectl rollout history deployment/<name> -n <namespace>

# Describe deployment
kubectl describe deployment <name> -n <namespace>
```

**Solution**:
```bash
# Rollback to previous version
kubectl rollout undo deployment/<name> -n <namespace>

# Or rollback to specific revision
kubectl rollout undo deployment/<name> --to-revision=2 -n <namespace>
```

**Reference**: `k8s-deploy.sh` includes automatic rollback on failure

---

## Challenge 04: Security and Compliance

### Issue: Security Scanner Failing
**Error**: Multiple vulnerabilities detected

**Solution**:
```bash
# Run comprehensive scan
./challenges/04-security-and-compliance/implementation/security-scanner.sh

# Address each category:

# 1. IaC issues (Checkov)
checkov -d . --framework terraform
# Fix: Update Terraform configurations

# 2. Container vulnerabilities (Trivy)
trivy image myimage:latest
# Fix: Update base image, patch dependencies

# 3. Secrets detected (Gitleaks)
gitleaks detect --source .
# Fix: Remove secrets, use secrets management

# 4. Code vulnerabilities (Semgrep)
semgrep --config auto .
# Fix: Update code to remove vulnerabilities
```

---

### Issue: Vault Unsealing Failed
**Error**: Vault pods stuck in initialization

**Debugging**:
```bash
# Check Vault status
kubectl exec -it vault-0 -n vault -- vault status

# View logs
kubectl logs vault-0 -n vault
```

**Solution**:
```bash
# Re-run setup script
./challenges/04-security-and-compliance/implementation/vault-setup.sh

# Manual unseal
kubectl exec -it vault-0 -n vault -- vault operator unseal <KEY1>
kubectl exec -it vault-0 -n vault -- vault operator unseal <KEY2>
kubectl exec -it vault-0 -n vault -- vault operator unseal <KEY3>

# Check vault-keys.json for unseal keys
cat vault-keys.json
```

---

### Issue: External Secrets Not Syncing
**Error**: ExternalSecret shows `SecretSyncedError`

**Debugging**:
```bash
# Check ExternalSecret status
kubectl get externalsecret -n <namespace>
kubectl describe externalsecret <name> -n <namespace>

# Check SecretStore
kubectl get secretstore -n <namespace>
kubectl describe secretstore <name> -n <namespace>

# Check operator logs
kubectl logs -n external-secrets-system deployment/external-secrets
```

**Solution**:
```bash
# Verify authentication
# For Vault: Check Kubernetes auth is configured
# For AWS: Check IRSA annotations
# For Azure: Check workload identity

# Test secret path manually
# For Vault:
vault kv get secret/data/app/database
```

**Reference**: See `secrets-management.sh`

---

### Issue: NetworkPolicy Blocking Traffic
**Symptoms**: Services cannot communicate

**Debugging**:
```bash
# Check NetworkPolicies
kubectl get networkpolicy -n <namespace>

# Describe policy
kubectl describe networkpolicy <name> -n <namespace>

# Test connectivity
kubectl run test --rm -it --image=busybox -- sh
wget -O- http://backend:8080
```

**Solution**:
```bash
# Temporarily remove policy for testing
kubectl delete networkpolicy <name> -n <namespace>

# Fix policy selectors
# Ensure labels match pods
kubectl get pods --show-labels
```

**Reference**: See `network-policies.yaml` for examples

---

## Challenge 05: Monitoring and Observability

### Issue: Prometheus Not Scraping Targets
**Error**: Targets show as "Down" in Prometheus UI

**Debugging**:
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n observability

# Verify service has correct labels
kubectl get svc -n <namespace> --show-labels

# Check Prometheus config
kubectl get prometheus -n observability -o yaml
```

**Solution**:
```bash
# Ensure pod has monitoring label
kubectl label pod <pod-name> monitoring=enabled

# Verify port name in service
# Must match ServiceMonitor
spec:
  ports:
    - name: metrics  # Important: name must match
      port: 9090
```

---

### Issue: Grafana Dashboards Not Loading
**Error**: "No data" in dashboard panels

**Debugging**:
```bash
# Check Grafana datasource
# UI: Configuration → Data Sources

# Test Prometheus connectivity
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
curl http://localhost:9090/api/v1/query?query=up

# Check dashboard queries
# Verify metric names exist in Prometheus
```

**Solution**:
```bash
# Re-import dashboard
kubectl apply -f challenges/05-monitoring-and-observability/implementation/grafana-dashboard.json

# Verify datasource is configured
# Should point to: http://prometheus-kube-prometheus-prometheus:9090
```

---

### Issue: Loki Not Receiving Logs
**Symptoms**: No logs visible in Grafana

**Debugging**:
```bash
# Check Promtail pods
kubectl get pods -n observability -l app=promtail

# View Promtail logs
kubectl logs -n observability -l app=promtail

# Test Loki directly
kubectl port-forward -n observability svc/loki 3100:3100
curl http://localhost:3100/ready
```

**Solution**:
```bash
# Verify Promtail configuration
kubectl get configmap -n observability loki-promtail

# Check label matchers
# Ensure namespace labels exist
kubectl get namespace <name> --show-labels
```

**Reference**: See `loki-config.yml` for configuration

---

### Issue: SLO Dashboard Shows No Data
**Symptoms**: SLO metrics missing

**Solution**:
```bash
# Ensure application exports required metrics
# Required for SLO tracking:
# - http_requests_total (with status label)
# - http_request_duration_seconds_bucket

# Run SLO dashboard script
./challenges/05-monitoring-and-observability/implementation/slo-dashboard.sh myapp

# Verify PromQL queries
# Test in Prometheus UI first
```

---

## Challenge 06: Platform Engineering

### Issue: Backstage Not Starting
**Error**: Backstage pods crash on startup

**Debugging**:
```bash
# Check pod logs
kubectl logs -n backstage deployment/backstage

# Common errors:
# 1. Database connection failed
kubectl get pods -n backstage -l app=postgres

# 2. Configuration error
kubectl get configmap -n backstage backstage-app-config
```

**Solution**:
```bash
# Verify database is running
kubectl exec -it postgres-0 -n backstage -- psql -U backstage -c "SELECT 1;"

# Check environment variables
kubectl describe pod -n backstage -l app=backstage | grep -A 10 "Environment:"

# Re-run setup
./challenges/06-platform-engineering/implementation/backstage-setup.sh
```

---

### Issue: Service Templates Not Working
**Error**: Template scaffolding fails

**Debugging**:
```bash
# Check template syntax
kubectl get configmap service-template -n backstage -o yaml

# View Backstage backend logs
kubectl logs -n backstage deployment/backstage -c backstage | grep "template"
```

**Solution**:
- Verify GitHub token has correct permissions
- Check template repository access
- Validate YAML syntax in template files

**Reference**: See `service-template.yaml`

---

## Challenge 07: DevSecOps

### Issue: DevSecOps Pipeline Failing
**Error**: Security checks failing in CI/CD

**Debugging**:
```bash
# Run pipeline locally
./challenges/07-devsecops/implementation/devsecops-full-pipeline.sh

# Check individual tools:
gitleaks detect --source .
semgrep --config auto .
trivy image myimage:latest
checkov -d .
```

**Solution**:
```bash
# Fix secrets
# Remove from git history
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch path/to/secret" \
  --prune-empty --tag-name-filter cat -- --all

# Fix code vulnerabilities
# Update dependencies
npm audit fix
pip-audit --fix

# Fix IaC issues
# Apply Checkov suggestions
```

---

### Issue: Falco Rules Too Noisy
**Symptoms**: Too many false positive alerts

**Solution**:
```bash
# Tune Falco rules
kubectl edit configmap falco-rules -n falco

# Add exceptions for known good behavior
# Example: Allow specific processes
- list: allowed_processes
  items: [node, npm, python]

# Adjust priority levels
# Change WARNING to INFO for non-critical rules
```

**Reference**: See `falco-rules.yaml`

---

### Issue: OPA Policy Blocking Valid Pods
**Error**: Pod admission denied

**Debugging**:
```bash
# Check OPA logs
kubectl logs -n opa deployment/opa

# Test policy locally
opa test policy-as-code.rego

# Evaluate specific case
opa eval -d policy.rego -i pod.json "data.kubernetes.admission.deny"
```

**Solution**:
```bash
# Update policy exceptions
# Add to trusted_containers list

# Or update pod to meet policy
# Add resource limits, security context, etc.
```

**Reference**: See `policy-as-code.rego`

---

## Challenge 08: AI/ML/LLM Ops

### Issue: MLflow Tracking Server Not Accessible
**Debugging**:
```bash
# Check MLflow server
kubectl get pods -n mlflow
kubectl logs -n mlflow deployment/mlflow-server

# Test connection
kubectl port-forward -n mlflow svc/mlflow 5000:5000
curl http://localhost:5000/health
```

**Solution**:
```bash
# Verify backend storage (S3, Azure Blob, etc.)
# Check credentials
kubectl get secret -n mlflow mlflow-secrets

# Re-deploy if needed
kubectl rollout restart deployment/mlflow-server -n mlflow
```

---

### Issue: Model Serving Inference Errors
**Error**: 500 errors from KServe

**Debugging**:
```bash
# Check InferenceService status
kubectl get inferenceservice -n <namespace>

# Check predictor logs
kubectl logs -n <namespace> -l serving.kubeflow.org/inferenceservice=<name>

# Verify model artifact exists
# Check S3/GCS bucket or PVC
```

**Solution**:
```bash
# Update model URI
kubectl edit inferenceservice <name> -n <namespace>

# Scale up if resource constrained
kubectl scale --replicas=3 inferenceservice/<name> -n <namespace>
```

---

## Challenge 09: Linux System Administration

### Issue: Security Hardening Script Fails
**Error**: Script exits with errors

**Debugging**:
```bash
# Run in debug mode
bash -x challenges/09-linux-system-administration/implementation/security-hardening.sh

# Check specific service
systemctl status fail2ban
systemctl status firewalld
```

**Solution**:
```bash
# Install missing dependencies
# Ubuntu/Debian:
sudo apt-get update
sudo apt-get install -y fail2ban ufw aide

# RHEL/CentOS:
sudo yum install -y fail2ban firewalld aide
```

---

### Issue: Backup System Failing
**Error**: Restic backup fails

**Debugging**:
```bash
# Check Restic repository
restic -r /path/to/repo snapshots

# View logs
journalctl -u restic-backup.service -n 50

# Test backup manually
restic -r /path/to/repo backup /data --dry-run
```

**Solution**:
```bash
# Initialize repository if needed
restic init -r /path/to/repo

# Check credentials
cat ~/.restic/credentials

# Verify backup destination is accessible
# For S3:
aws s3 ls s3://bucket-name/
```

**Reference**: See `backup-system.sh`

---

## Quick Debugging Commands

### Kubernetes
```bash
# Pod debugging
kubectl get events --sort-by='.lastTimestamp' -n <namespace>
kubectl debug <pod> -it --image=busybox
kubectl exec -it <pod> -- sh

# Resource usage
kubectl top nodes
kubectl top pods -n <namespace>

# Configuration
kubectl get cm,secret -n <namespace>
kubectl describe pod <pod> -n <namespace>
```

### Docker
```bash
# Container logs
docker logs <container-id>
docker logs -f <container-id>  # Follow

# Inspect
docker inspect <container-id>
docker stats <container-id>

# Enter container
docker exec -it <container-id> sh
```

### Terraform
```bash
# Debug
TF_LOG=DEBUG terraform apply

# State operations
terraform state list
terraform state show <resource>
terraform refresh
```

---

## Getting Help

### 1. Check Implementation Files
Every challenge has working implementation files. Compare your setup against these.

### 2. Review problem.md and solution.md
Each challenge folder contains detailed problem descriptions and solutions.

### 3. Enable Debug Logging
Most tools support verbose logging:
```bash
# Terraform
export TF_LOG=DEBUG

# Kubernetes
kubectl <command> -v=9

# Docker
dockerd --debug
```

### 4. Community Resources
- **GitHub Issues**: Check if others have faced the same issue
- **Stack Overflow**: Search for specific error messages
- **Tool Documentation**: Official docs often have troubleshooting sections
- **Slack Communities**: CNCF, Kubernetes, HashiCorp channels

### 5. Create Minimal Reproduction
Isolate the issue with minimal configuration for easier debugging.

---

## Prevention Best Practices

1. **Use Version Control**: Track all changes
2. **Test in Non-Production**: Validate before production deployment
3. **Monitor Continuously**: Catch issues early
4. **Automate Testing**: CI/CD with comprehensive tests
5. **Document Changes**: Keep runbooks updated
6. **Regular Backups**: Ensure data can be recovered
7. **Security Scanning**: Shift left on security
8. **Resource Limits**: Prevent resource exhaustion
9. **Health Checks**: Enable liveness and readiness probes
10. **Logging**: Comprehensive, structured logging

---

## Still Stuck?

If you're still experiencing issues after following this guide:

1. **Review the specific challenge's implementation files** - they contain working solutions
2. **Check the problem.md and solution.md** - they explain the context
3. **Open an issue on GitHub** with:
   - Error messages
   - Steps to reproduce
   - Environment details
   - What you've already tried

Remember: Troubleshooting is a core DevOps skill. Each issue solved makes you stronger! 💪