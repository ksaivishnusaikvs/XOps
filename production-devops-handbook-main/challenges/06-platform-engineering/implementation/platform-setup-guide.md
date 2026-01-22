# Platform Engineering - Step-by-Step Implementation Guide

## Step 1: Deploy Backstage (IDP Core)

### 1.1 Prerequisites
```bash
# Install Node.js 18+
nvm install 18
nvm use 18

# Install Yarn
npm install -g yarn

# Install Docker (for TechDocs)
```

### 1.2 Create Backstage App
```bash
npx @backstage/create-app@latest

# Follow prompts
cd my-backstage-app
```

### 1.3 Configure Authentication
```bash
# Set up GitHub OAuth App at https://github.com/settings/developers
# Then update app-config.yaml

auth:
  environment: production
  providers:
    github:
      production:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}
```

### 1.4 Run Locally
```bash
yarn dev
# Access at http://localhost:3000
```

## Step 2: Create Software Templates

### 2.1 Create Template Directory Structure
```bash
mkdir -p templates/microservice-template/{template,skeleton}
cd templates/microservice-template
```

### 2.2 Create Template Skeleton
```bash
# skeleton/catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: ${{ values.serviceName }}
  description: ${{ values.description }}
  annotations:
    github.com/project-slug: ${{ values.orgName }}/${{ values.serviceName }}
spec:
  type: service
  lifecycle: experimental
  owner: ${{ values.owner }}
```

### 2.3 Register Template in Backstage
```yaml
# app-config.yaml
catalog:
  locations:
    - type: file
      target: ../../templates/microservice-template/template.yaml
      rules:
        - allow: [Template]
```

## Step 3: Integrate with Kubernetes

### 3.1 Install Kubernetes Plugin
```bash
yarn --cwd packages/app add @backstage/plugin-kubernetes
yarn --cwd packages/backend add @backstage/plugin-kubernetes-backend
```

### 3.2 Configure Kubernetes Backend
```typescript
// packages/backend/src/plugins/kubernetes.ts
import { KubernetesBuilder } from '@backstage/plugin-kubernetes-backend';
import { Router } from 'express';
import { PluginEnvironment } from '../types';

export default async function createPlugin(
  env: PluginEnvironment,
): Promise<Router> {
  const { router } = await KubernetesBuilder.createBuilder({
    logger: env.logger,
    config: env.config,
  }).build();
  return router;
}
```

### 3.3 Configure Kubernetes Clusters
```yaml
# app-config.yaml
kubernetes:
  serviceLocatorMethod:
    type: 'multiTenant'
  clusterLocatorMethods:
    - type: 'config'
      clusters:
        - url: https://kubernetes.default.svc
          name: local
          authProvider: 'serviceAccount'
          skipTLSVerify: false
          skipMetricsLookup: false
```

## Step 4: Set Up Service Catalog

### 4.1 Create System Definition
```yaml
# catalog/systems.yaml
apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: ecommerce-platform
  description: E-commerce platform
spec:
  owner: platform-team
  domain: retail
---
apiVersion: backstage.io/v1alpha1
kind: Domain
metadata:
  name: retail
  description: Retail domain
spec:
  owner: product-team
```

### 4.2 Define Components
```yaml
# catalog/components.yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: payment-service
  description: Payment processing service
  tags:
    - java
    - spring-boot
  annotations:
    github.com/project-slug: myorg/payment-service
spec:
  type: service
  lifecycle: production
  owner: payments-team
  system: ecommerce-platform
  dependsOn:
    - resource:payments-database
  providesApis:
    - payment-api
```

### 4.3 Register in Catalog
```yaml
# app-config.yaml
catalog:
  locations:
    - type: file
      target: ../../catalog/systems.yaml
    - type: file
      target: ../../catalog/components.yaml
```

## Step 5: Integrate Monitoring and Observability

### 5.1 Add Prometheus Plugin
```bash
yarn --cwd packages/app add @roadiehq/backstage-plugin-prometheus
```

### 5.2 Configure Prometheus
```yaml
# app-config.yaml
proxy:
  '/prometheus/api':
    target: 'http://prometheus-server.monitoring.svc.cluster.local'
    changeOrigin: true
    pathRewrite:
      '^/proxy/prometheus/api': '/api'
```

### 5.3 Add Grafana Plugin
```bash
yarn --cwd packages/app add @k-phoen/backstage-plugin-grafana
```

### 5.4 Configure Grafana
```yaml
# app-config.yaml
grafana:
  domain: https://grafana.example.com
  unifiedAlerting: true
```

## Step 6: Implement TechDocs

### 6.1 Install TechDocs
```bash
yarn --cwd packages/app add @backstage/plugin-techdocs
yarn --cwd packages/backend add @backstage/plugin-techdocs-backend
```

### 6.2 Configure TechDocs
```yaml
# app-config.yaml
techdocs:
  builder: 'local'
  generator:
    runIn: 'docker'
  publisher:
    type: 'local'
```

### 6.3 Create Documentation
```bash
# In your service repository
mkdir docs
cat > docs/index.md <<EOF
# Payment Service

## Overview
Payment processing microservice

## Features
- Credit card processing
- Refunds
- Webhooks
EOF

cat > mkdocs.yml <<EOF
site_name: Payment Service
nav:
  - Home: index.md

plugins:
  - techdocs-core
EOF
```

## Step 7: Create Self-Service Actions

### 7.1 Create Custom Scaffolder Action
```typescript
// plugins/scaffolder-backend/src/actions/custom/createJiraTicket.ts
import { createTemplateAction } from '@backstage/plugin-scaffolder-node';
import fetch from 'node-fetch';

export const createJiraTicketAction = () => {
  return createTemplateAction({
    id: 'jira:ticket:create',
    schema: {
      input: {
        type: 'object',
        required: ['summary', 'project'],
        properties: {
          summary: {
            title: 'Issue Summary',
            type: 'string',
          },
          project: {
            title: 'Project Key',
            type: 'string',
          },
          description: {
            title: 'Description',
            type: 'string',
          },
        },
      },
      output: {
        type: 'object',
        properties: {
          ticketKey: {
            type: 'string',
          },
        },
      },
    },
    async handler(ctx) {
      const { summary, project, description } = ctx.input;
      
      const response = await fetch('https://jira.example.com/rest/api/2/issue', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${process.env.JIRA_TOKEN}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          fields: {
            project: { key: project },
            summary,
            description,
            issuetype: { name: 'Task' },
          },
        }),
      });
      
      const data = await response.json();
      ctx.output('ticketKey', data.key);
      ctx.logger.info(`Created JIRA ticket: ${data.key}`);
    },
  });
};
```

### 7.2 Register Custom Action
```typescript
// packages/backend/src/plugins/scaffolder.ts
import { createJiraTicketAction } from './actions/custom/createJiraTicket';

const actions = [
  ...builtInActions,
  createJiraTicketAction(),
];
```

## Step 8: Implement RBAC

### 8.1 Install Permission Plugin
```bash
yarn --cwd packages/backend add @backstage/plugin-permission-backend
yarn --cwd packages/backend add @backstage/plugin-permission-node
```

### 8.2 Define Permissions
```typescript
// plugins/permission-backend/src/policy.ts
import { PolicyDecision } from '@backstage/plugin-permission-common';
import { BackstageIdentityResponse } from '@backstage/plugin-auth-node';

export class CustomPermissionPolicy {
  async handle(
    request: PolicyQuery,
    user?: BackstageIdentityResponse,
  ): Promise<PolicyDecision> {
    if (request.permission.name === 'catalog.entity.delete') {
      return {
        result: user?.identity.ownershipEntityRefs.includes(
          request.permission.resourceRef
        ) ? AuthorizeResult.ALLOW : AuthorizeResult.DENY,
      };
    }
    
    return { result: AuthorizeResult.ALLOW };
  }
}
```

## Step 9: Deploy to Kubernetes

### 9.1 Build Docker Image
```dockerfile
# Dockerfile
FROM node:18-bullseye-slim

WORKDIR /app

# Install dependencies
COPY package.json yarn.lock ./
COPY packages packages

RUN yarn install --frozen-lockfile --production

# Build
RUN yarn tsc
RUN yarn build

# Run
CMD ["node", "packages/backend", "--config", "app-config.yaml"]
```

### 9.2 Create Kubernetes Manifests
```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backstage
  namespace: platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backstage
  template:
    metadata:
      labels:
        app: backstage
    spec:
      containers:
      - name: backstage
        image: backstage:latest
        ports:
        - containerPort: 7007
        env:
        - name: POSTGRES_HOST
          value: postgres
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-secrets
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secrets
              key: password
        volumeMounts:
        - name: app-config
          mountPath: /app/app-config.yaml
          subPath: app-config.yaml
      volumes:
      - name: app-config
        configMap:
          name: backstage-config
```

### 9.3 Deploy
```bash
kubectl apply -f k8s/
```

## Step 10: Implement Developer Portal Features

### 10.1 Create Homepage
```typescript
// packages/app/src/components/home/HomePage.tsx
import { HomePageToolkit } from '@backstage/plugin-home';
import { Content, Header, Page } from '@backstage/core-components';
import { HomePageStarredEntities } from '@backstage/plugin-home';

export const HomePage = () => (
  <Page themeId="home">
    <Header title="Welcome to DevPortal" />
    <Content>
      <Grid container spacing={3}>
        <Grid item xs={12} md={6}>
          <HomePageToolkit
            tools={[
              {
                url: '/create',
                label: 'Create New Service',
                icon: <CreateComponentIcon />,
              },
              {
                url: '/catalog',
                label: 'Service Catalog',
                icon: <CatalogIcon />,
              },
            ]}
          />
        </Grid>
        <Grid item xs={12} md={6}>
          <HomePageStarredEntities />
        </Grid>
      </Grid>
    </Content>
  </Page>
);
```

### 10.2 Add Search
```bash
yarn --cwd packages/app add @backstage/plugin-search
yarn --cwd packages/backend add @backstage/plugin-search-backend
yarn --cwd packages/backend add @backstage/plugin-search-backend-module-catalog
```

### 10.3 Configure Search
```typescript
// packages/backend/src/plugins/search.ts
import { CatalogCollatorFactory } from '@backstage/plugin-search-backend-module-catalog';

const indexBuilder = new IndexBuilder({
  logger: env.logger,
  searchEngine: new LunrSearchEngine({ logger: env.logger }),
});

indexBuilder.addCollator({
  defaultRefreshIntervalSeconds: 600,
  factory: CatalogCollatorFactory.fromConfig(env.config, {
    discovery: env.discovery,
    tokenManager: env.tokenManager,
  }),
});
```

## Platform Features Checklist

- [ ] Service catalog with templates
- [ ] Self-service actions (create repo, namespace, etc.)
- [ ] Kubernetes integration
- [ ] CI/CD visibility
- [ ] Monitoring/observability integration
- [ ] TechDocs for documentation
- [ ] Search functionality
- [ ] RBAC/Permissions
- [ ] Custom branding
- [ ] Developer homepage
- [ ] API documentation
- [ ] Scorecards for service quality

## Golden Paths to Implement

1. **New Service Creation**
   - Create GitHub repository
   - Set up CI/CD pipeline
   - Create Kubernetes namespace
   - Configure monitoring
   - Generate documentation

2. **Database Provisioning**
   - Request database instance
   - Set up backups
   - Configure access controls
   - Generate credentials

3. **Environment Setup**
   - Clone existing environment
   - Configure resources
   - Set up networking
   - Deploy applications
