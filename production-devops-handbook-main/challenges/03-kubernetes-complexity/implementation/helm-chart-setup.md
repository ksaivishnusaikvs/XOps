# Kubernetes Simplification - Step-by-Step Guide

## Step 1: Use Helm for Package Management

### 1.1 Install Helm
```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Windows
choco install kubernetes-helm
```

### 1.2 Create Helm Chart
```bash
helm create myapp
cd myapp/
```

### 1.3 Customize values.yaml
```yaml
replicaCount: 3

image:
  repository: myapp
  pullPolicy: IfNotPresent
  tag: "latest"

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: myapp-tls
      hosts:
        - myapp.example.com

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

### 1.4 Install Chart
```bash
helm install myapp ./myapp -n myapp --create-namespace
```

### 1.5 Upgrade Application
```bash
helm upgrade myapp ./myapp -n myapp --set image.tag=v1.2.0
```

## Step 2: Implement GitOps with ArgoCD

### 2.1 Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 2.2 Access ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 2.3 Create Application
```yaml
# application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/myapp
    targetRevision: HEAD
    path: k8s/
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

```bash
kubectl apply -f application.yaml
```

## Step 3: Use Kustomize for Environment Management

### 3.1 Create Base Configuration
```bash
mkdir -p k8s/base k8s/overlays/{dev,staging,prod}
```

```yaml
# k8s/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml

commonLabels:
  app: myapp
```

### 3.2 Create Environment Overlays
```yaml
# k8s/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base

namespace: myapp-prod

replicas:
  - name: myapp
    count: 5

images:
  - name: myapp
    newTag: v1.2.0

patchesStrategicMerge:
  - replica-patch.yaml
  - resource-patch.yaml
```

### 3.3 Apply Kustomize
```bash
kubectl apply -k k8s/overlays/prod
```

## Step 4: Implement Secrets Management

### 4.1 Install Sealed Secrets
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Install kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-linux-amd64 -O kubeseal
chmod +x kubeseal
sudo mv kubeseal /usr/local/bin/
```

### 4.2 Create Sealed Secret
```bash
# Create regular secret
kubectl create secret generic myapp-secrets \
  --from-literal=db-password=mypassword \
  --dry-run=client -o yaml > secret.yaml

# Seal it
kubeseal -f secret.yaml -w sealed-secret.yaml

# Apply sealed secret (safe to commit to git)
kubectl apply -f sealed-secret.yaml
```

### 4.3 Alternative: Use External Secrets Operator
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace
```

## Step 5: Implement Resource Quotas and Limits

### 5.1 Create ResourceQuota
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: myapp-quota
  namespace: myapp
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "50"
    services: "10"
    persistentvolumeclaims: "5"
```

### 5.2 Create LimitRange
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: myapp-limits
  namespace: myapp
spec:
  limits:
  - max:
      cpu: "2"
      memory: 2Gi
    min:
      cpu: 50m
      memory: 64Mi
    default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
```

## Step 6: Set Up Monitoring and Logging

### 6.1 Install Prometheus Stack
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace
```

### 6.2 Install Loki for Logging
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack -n monitoring
```

### 6.3 Access Grafana
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Default credentials: admin / prom-operator
```

## Step 7: Implement Security Best Practices

### 7.1 Install OPA Gatekeeper
```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml
```

### 7.2 Create Constraint Template
```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          properties:
            labels:
              type: array
              items: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg, "details": {"missing_labels": missing}}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Missing required labels: %v", [missing])
        }
```

### 7.3 Apply Constraint
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-app-label
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
  parameters:
    labels: ["app", "environment", "team"]
```

## Step 8: Use kubectl Plugins for Productivity

### 8.1 Install krew (kubectl plugin manager)
```bash
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
```

### 8.2 Install Useful Plugins
```bash
kubectl krew install ctx        # Switch contexts
kubectl krew install ns         # Switch namespaces
kubectl krew install tree       # Show resource tree
kubectl krew install neat       # Clean up kubectl output
kubectl krew install stern      # Multi-pod log tailing
kubectl krew install whoami     # Show current user
kubectl krew install resource-capacity  # Show resource usage
```

## Step 9: Implement Backup Strategy

### 9.1 Install Velero
```bash
kubectl apply -f https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
```

### 9.2 Configure Backup
```bash
velero backup create myapp-backup \
  --include-namespaces myapp \
  --storage-location default \
  --ttl 720h
```

### 9.3 Schedule Regular Backups
```bash
velero schedule create myapp-daily \
  --schedule="0 2 * * *" \
  --include-namespaces myapp
```

## Step 10: Create Runbooks and Documentation

### 10.1 Common kubectl Commands
```bash
# Get all resources
kubectl get all -n myapp

# Describe pod
kubectl describe pod <pod-name> -n myapp

# View logs
kubectl logs -f <pod-name> -n myapp

# Execute command in pod
kubectl exec -it <pod-name> -n myapp -- /bin/sh

# Port forward
kubectl port-forward svc/myapp 8080:80 -n myapp

# Scale deployment
kubectl scale deployment myapp --replicas=5 -n myapp

# Rollback deployment
kubectl rollout undo deployment/myapp -n myapp

# Check rollout status
kubectl rollout status deployment/myapp -n myapp
```

### 10.2 Troubleshooting Checklist
1. Check pod status: `kubectl get pods`
2. View pod logs: `kubectl logs <pod>`
3. Describe pod: `kubectl describe pod <pod>`
4. Check events: `kubectl get events --sort-by='.lastTimestamp'`
5. Verify resources: `kubectl top nodes` and `kubectl top pods`
6. Check network policies: `kubectl get networkpolicies`
7. Verify service endpoints: `kubectl get endpoints`

## Step 11: Implement Cost Optimization

### 11.1 Use Vertical Pod Autoscaler
```bash
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/download/vertical-pod-autoscaler-0.13.0/vpa-v0.13.0.yaml
```

### 11.2 Create VPA Resource
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: myapp-vpa
  namespace: myapp
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: Deployment
    name: myapp
  updatePolicy:
    updateMode: "Auto"
```

## Complexity Reduction Checklist

- [ ] Use Helm charts for templating
- [ ] Implement GitOps with ArgoCD/FluxCD
- [ ] Use Kustomize for environment-specific configs
- [ ] Implement proper RBAC
- [ ] Use Network Policies
- [ ] Implement Pod Security Standards
- [ ] Set up centralized logging
- [ ] Configure monitoring and alerting
- [ ] Implement secrets management
- [ ] Document common operations
- [ ] Create automated backups
- [ ] Use kubectl plugins for efficiency
