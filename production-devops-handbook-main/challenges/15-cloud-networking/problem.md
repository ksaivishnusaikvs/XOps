# Challenge 15: Cloud Networking & Security

## Business Context
TechSecure Inc., a healthcare SaaS provider (HIPAA-compliant), manages patient data for 300+ hospitals across their multi-cloud infrastructure. Their network architecture has critical security gaps:

- **3 security breaches in 18 months** (avg cost: $450K each)
- **Flat network topology** - no micro-segmentation, lateral movement risk
- **Public internet exposure** for internal services (database endpoints accessible externally)
- **No zero-trust architecture** - implicit trust model
- **Failed compliance audits** (HIPAA, SOC 2) due to network controls
- **DDoS vulnerability** - 12-hour outage last quarter ($2M revenue loss)

## Problems

### 1. **Network Segmentation Failure**
- Flat VPC design with all subnets in same security zone
- No segmentation between dev/staging/production
- Database servers accessible from web tier without restrictions
- Cost: 1 breach = $450K, regulatory fines = $100K

### 2. **No Zero-Trust Implementation**
- Service-to-service communication over plain HTTP
- No mutual TLS between microservices
- Static credentials in application code
- Insider threat risk

### 3. **Inadequate DDoS Protection**
- No CloudFlare, AWS Shield, or Azure DDoS protection
- Application layer attacks overwhelm origin servers
- Last incident: 12-hour outage, $2M revenue loss

### 4. **Poor Firewall & WAF Coverage**
- Security groups with 0.0.0.0/0 rules (18 instances)
- No Web Application Firewall for OWASP Top 10
- SQL injection blocked only at application layer
- XSS vulnerabilities in legacy apps

### 5. **Kubernetes Network Policy Gaps**
- Default namespace allows all pod-to-pod traffic
- No NetworkPolicy enforcement (CNI doesn't support)
- Services exposed publicly without authentication
- Secrets transmitted in plain text between pods

### 6. **Multi-Cloud Connectivity Chaos**
- AWS, Azure, GCP workloads need interconnection
- Site-to-site VPN with single point of failure
- No direct cloud-to-cloud peering (expensive egress: $0.09/GB)
- Average latency: 120ms (SLA requires <50ms)

### 7. **No Network Monitoring/Visibility**
- Cannot trace requests across services
- No flow logs or packet capture
- Security incidents discovered days later
- Mean Time to Detect (MTTD): 14 days

### 8. **Compliance Violations**
- HIPAA requires encryption in transit (missing for internal traffic)
- SOC 2 requires network segmentation (flat network)
- Data residency laws require regional isolation (single global VPC)
- Audit findings: 27 critical network controls missing

## Impact
- **Security incidents**: 3 breaches, $1.35M total cost
- **Compliance risk**: Failed HIPAA audit, potential $50K/day fines
- **Downtime**: 12-hour DDoS outage = $2M revenue loss
- **Opportunity cost**: Can't pursue enterprise contracts (require SOC 2 Type II)
- **Engineering overhead**: 30% of sprint capacity spent on security firefighting

## Requirements
1. Design secure multi-tier VPC architecture with proper segmentation
2. Implement zero-trust networking with mutual TLS
3. Deploy comprehensive DDoS protection (L3/L4/L7)
4. Configure Web Application Firewall with OWASP rules
5. Enforce Kubernetes NetworkPolicies for pod isolation
6. Establish multi-cloud connectivity with redundancy
7. Implement network monitoring and flow log analysis
8. Achieve HIPAA and SOC 2 compliance for network controls
