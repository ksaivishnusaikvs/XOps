# DevOps Resources & Tool Guide

This comprehensive resource guide covers all tools, technologies, and learning materials referenced in our 9 DevOps challenges. Each section maps to specific implementations in the repository.

## Table of Contents
- [Infrastructure as Code Tools](#infrastructure-as-code-tools)
- [CI/CD Tools](#cicd-tools)
- [Container & Orchestration](#container--orchestration)
- [Security Tools](#security-tools)
- [Monitoring & Observability](#monitoring--observability)
- [Platform Engineering](#platform-engineering)
- [AI/ML Tools](#aiml-tools)
- [Books & Articles](#books--articles)
- [Courses & Certifications](#courses--certifications)
- [Communities](#communities)

---

## Infrastructure as Code Tools

### Terraform
- **Purpose**: Infrastructure provisioning and management
- **Used in**: Challenge 01 - Infrastructure as Code
- **Key Features**: State management, provider ecosystem, HCL syntax
- **Resources**:
  - [Official Documentation](https://www.terraform.io/docs)
  - [Terraform Registry](https://registry.terraform.io/)
  - [Best Practices Guide](https://www.terraform-best-practices.com/)
- **Implementation**: See `/challenges/01-infrastructure-as-code/implementation/`

### tflint
- **Purpose**: Terraform linting and validation
- **Integration**: Pre-commit hooks
- **Documentation**: https://github.com/terraform-linters/tflint

### Checkov
- **Purpose**: IaC security scanning
- **Scans**: Terraform, Kubernetes, Dockerfile, CloudFormation
- **Documentation**: https://www.checkov.io/
- **Implementation**: Used in security-scanner.sh

---

## CI/CD Tools

### GitHub Actions
- **Purpose**: CI/CD automation
- **Used in**: Challenge 02 - CI/CD Optimization
- **Features**: Matrix builds, caching, reusable workflows
- **Implementation**: See `advanced-caching.yml`
- **Resources**:
  - [GitHub Actions Docs](https://docs.github.com/en/actions)
  - [Actions Marketplace](https://github.com/marketplace?type=actions)

### Docker BuildKit
- **Purpose**: Enhanced Docker build performance
- **Features**: Parallel builds, advanced caching, secrets management
- **Documentation**: https://docs.docker.com/build/buildkit/
- **Implementation**: See `docker-optimization.sh`

### Jenkins
- **Purpose**: Open-source automation server
- **Use Cases**: Complex pipelines, enterprise environments
- **Resources**: https://www.jenkins.io/doc/

---

## Container & Orchestration

### Docker
- **Purpose**: Container platform
- **Best Practices**: Multi-stage builds, minimal images, non-root users
- **Documentation**: https://docs.docker.com/
- **Implementation**: See `Dockerfile.optimized`

### Kubernetes
- **Purpose**: Container orchestration
- **Used in**: Challenges 03, 04, 05, 06, 07
- **Key Concepts**: Deployments, Services, HPA, PDB, NetworkPolicies
- **Resources**:
  - [Official Documentation](https://kubernetes.io/docs/)
  - [Kubernetes Patterns Book](https://k8spatterns.io/)
- **Implementations**:
  - Production manifests: `production-deployment.yaml`
  - Safe deployment: `k8s-deploy.sh`
  - Network security: `network-policies.yaml`

### Helm
- **Purpose**: Kubernetes package manager
- **Use Cases**: Application deployment, chart management
- **Documentation**: https://helm.sh/docs/
- **Implementation**: Used in observability and Vault setup scripts

### Kustomize
- **Purpose**: Kubernetes configuration management
- **Features**: Environment overlays, patches, no templating
- **Documentation**: https://kustomize.io/
- **Implementation**: See `kustomize-*.yaml` files

### Kubeflow
- **Purpose**: ML workflow orchestration on Kubernetes
- **Used in**: Challenge 08 - AI/ML/LLM Ops
- **Documentation**: https://www.kubeflow.org/

### KServe
- **Purpose**: Model serving on Kubernetes
- **Features**: Auto-scaling, canary deployments, multi-framework support
- **Documentation**: https://kserve.github.io/

---

## Security Tools

### Trivy
- **Purpose**: Container vulnerability scanner
- **Scans**: Images, filesystems, git repositories
- **Documentation**: https://aquasecurity.github.io/trivy/
- **Implementation**: See `security-scanner.sh`

### Gitleaks
- **Purpose**: Secret detection in git repositories
- **Features**: Custom rules, baseline scanning
- **Documentation**: https://github.com/gitleaks/gitleaks
- **Implementation**: Used in DevSecOps pipeline

### Semgrep
- **Purpose**: SAST (Static Application Security Testing)
- **Features**: Custom rules, multi-language support
- **Documentation**: https://semgrep.dev/
- **Implementation**: See `devsecops-full-pipeline.sh`

### HashiCorp Vault
- **Purpose**: Secrets management
- **Features**: Dynamic secrets, encryption as a service, PKI
- **Documentation**: https://www.vaultproject.io/docs
- **Implementation**: See `vault-setup.sh`

### External Secrets Operator
- **Purpose**: Sync external secrets into Kubernetes
- **Backends**: Vault, AWS, Azure, GCP
- **Documentation**: https://external-secrets.io/
- **Implementation**: See `secrets-management.sh`

### Falco
- **Purpose**: Runtime security monitoring
- **Features**: Detect anomalous behavior in containers
- **Documentation**: https://falco.org/
- **Implementation**: See `falco-rules.yaml`

### Open Policy Agent (OPA)
- **Purpose**: Policy as code
- **Use Cases**: Kubernetes admission control, API authorization
- **Documentation**: https://www.openpolicyagent.org/
- **Implementation**: See `policy-as-code.rego`

---

## Monitoring & Observability

### Prometheus
- **Purpose**: Metrics collection and alerting
- **Used in**: Challenge 05 - Monitoring and Observability
- **Features**: PromQL, service discovery, alerting
- **Documentation**: https://prometheus.io/docs/
- **Implementation**: See `observability-stack-setup.sh`

### Grafana
- **Purpose**: Metrics visualization and dashboards
- **Features**: Multi-source support, alerting, templating
- **Documentation**: https://grafana.com/docs/
- **Implementation**: See `grafana-dashboard.json`

### Loki
- **Purpose**: Log aggregation
- **Features**: LogQL, label-based indexing, cost-effective
- **Documentation**: https://grafana.com/docs/loki/
- **Implementation**: See `loki-config.yml`

### Jaeger
- **Purpose**: Distributed tracing
- **Features**: Trace visualization, dependency analysis
- **Documentation**: https://www.jaegertracing.io/docs/
- **Implementation**: Deployed via observability stack

### Alertmanager
- **Purpose**: Alert routing and notification
- **Features**: Grouping, silencing, routing
- **Documentation**: https://prometheus.io/docs/alerting/alertmanager/

---

## Platform Engineering

### Backstage
- **Purpose**: Internal developer platform
- **Used in**: Challenge 06 - Platform Engineering
- **Features**: Service catalog, software templates, TechDocs
- **Documentation**: https://backstage.io/docs/
- **Implementation**: See `backstage-setup.sh` and `service-template.yaml`

### Backstage Plugins
- **Kubernetes**: View cluster resources
- **TechDocs**: Documentation platform
- **Cost Insights**: Cloud cost tracking
- **Catalog**: Service discovery

---

## AI/ML Tools

### MLflow
- **Purpose**: ML experiment tracking and model registry
- **Used in**: Challenge 08 - AI/ML/LLM Ops
- **Documentation**: https://mlflow.org/docs/
- **Implementation**: See `/challenges/08-ai-ml-llm-ops/implementation/`

### LangChain
- **Purpose**: LLM application framework
- **Use Cases**: RAG systems, agents, chains
- **Documentation**: https://python.langchain.com/

### ChromaDB
- **Purpose**: Vector database for embeddings
- **Use Cases**: RAG, semantic search
- **Documentation**: https://www.trychroma.com/

---

## Books & Articles

### Essential Books
1. **The Phoenix Project** by Gene Kim
   - DevOps principles through narrative
   - Focus: Cultural transformation

2. **Accelerate** by Nicole Forsgren, Jez Humble, Gene Kim
   - Research-backed DevOps practices
   - Focus: Metrics and high-performance

3. **Site Reliability Engineering** by Google
   - SRE principles and practices
   - Free online: https://sre.google/books/

4. **Kubernetes Patterns** by Bilgin Ibryam, Roland Huß
   - Design patterns for K8s
   - Focus: Cloud-native applications

5. **Terraform: Up & Running** by Yevgeniy Brikman
   - Comprehensive IaC guide
   - Focus: Best practices and patterns

6. **Continuous Delivery** by Jez Humble, David Farley
   - CD principles and practices
   - Focus: Reliable software releases

7. **Building Secure & Reliable Systems** by Google
   - Security and reliability together
   - Free online: https://sre.google/books/

### Key Articles & Methodologies
- **The Twelve-Factor App**: https://12factor.net/
- **DORA Metrics**: https://www.devops-research.com/research.html
- **GitOps Principles**: https://opengitops.dev/
- **CIS Benchmarks**: https://www.cisecurity.org/cis-benchmarks/

---

## Courses & Certifications

### Recommended Courses
1. **Kubernetes Certifications (CNCF)**
   - CKA (Certified Kubernetes Administrator)
   - CKAD (Certified Kubernetes Application Developer)
   - CKS (Certified Kubernetes Security Specialist)

2. **HashiCorp Certifications**
   - Terraform Associate
   - Vault Associate

3. **Cloud Provider Certifications**
   - AWS Certified DevOps Engineer
   - Azure DevOps Engineer Expert
   - Google Cloud Professional DevOps Engineer

### Online Learning Platforms
- **A Cloud Guru**: Cloud and DevOps courses
- **Linux Academy**: Infrastructure and operations
- **Udemy**: Individual tool courses (Terraform, Kubernetes, etc.)
- **Coursera**: University-backed DevOps programs
- **KodeKloud**: Hands-on labs for Kubernetes, Docker, Terraform

---

## Communities

### Online Communities
- **r/devops** (Reddit): https://reddit.com/r/devops
- **DevOps Subreddit**: Daily discussions and news
- **CNCF Slack**: https://slack.cncf.io/
- **Kubernetes Slack**: For K8s-specific questions
- **HashiCorp Community**: https://discuss.hashicorp.com/

### Conferences
- **KubeCon + CloudNativeCon**: Premier Kubernetes conference
- **DevOps Enterprise Summit**: Enterprise DevOps practices
- **HashiConf**: HashiCorp technologies
- **AWS re:Invent**: AWS and cloud DevOps

### Blogs & Newsletters
- **DevOps.com**: Industry news and insights
- **The New Stack**: Cloud-native technologies
- **Kubernetes Blog**: Official K8s updates
- **HashiCorp Blog**: Terraform, Vault updates
- **CNCF Blog**: Cloud-native ecosystem

### Podcasts
- **The Kubernetes Podcast**: Weekly K8s news
- **DevOps Paradox**: DevOps culture and practices
- **Software Engineering Daily**: Technical deep dives

---

## Tool Comparison & Selection

### When to Use What

**IaC Tools**:
- Terraform: Multi-cloud, declarative
- Pulumi: Programming languages for IaC
- CloudFormation: AWS-specific

**CI/CD**:
- GitHub Actions: GitHub-native, easy to start
- GitLab CI: Integrated with GitLab
- Jenkins: Complex pipelines, enterprise
- ArgoCD: GitOps for Kubernetes

**Monitoring**:
- Prometheus + Grafana: Self-hosted, open-source
- Datadog: SaaS, comprehensive
- New Relic: APM and infrastructure

**Secrets Management**:
- HashiCorp Vault: Enterprise-grade, multi-cloud
- AWS Secrets Manager: AWS-native
- Azure Key Vault: Azure-native

---

## Quick Start Guide

### For Each Challenge

1. **Infrastructure as Code** → Start with Terraform documentation
2. **CI/CD Optimization** → Learn GitHub Actions, Docker BuildKit
3. **Kubernetes** → Get CKA/CKAD, practice with Minikube
4. **Security** → Try Trivy, Gitleaks, Checkov locally
5. **Monitoring** → Deploy Prometheus + Grafana stack
6. **Platform Engineering** → Explore Backstage demos
7. **DevSecOps** → Integrate security tools in CI/CD
8. **AI/ML Ops** → Start with MLflow experiments
9. **Linux Admin** → Practice CIS hardening guidelines

---

## Contributing to This Resource Guide

Found a great resource? Submit a PR to add it! We welcome:
- Tool recommendations
- Learning resources
- Best practice articles
- Community links