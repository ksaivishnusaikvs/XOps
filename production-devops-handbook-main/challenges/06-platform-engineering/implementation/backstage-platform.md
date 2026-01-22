# Platform Engineering - Internal Developer Platform (IDP)

## Overview
This template provides a foundation for building an Internal Developer Platform using Backstage.

## Components

### 1. Backstage Core Configuration

```yaml
# app-config.yaml
app:
  title: Developer Platform
  baseUrl: http://localhost:3000

organization:
  name: My Company

backend:
  baseUrl: http://localhost:7007
  listen:
    port: 7007
  cors:
    origin: http://localhost:3000
    methods: [GET, POST, PUT, DELETE]
    credentials: true
  database:
    client: better-sqlite3
    connection: ':memory:'
  cache:
    store: memory

integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}
  gitlab:
    - host: gitlab.com
      token: ${GITLAB_TOKEN}

proxy:
  '/prometheus/api':
    target: 'http://prometheus:9090/api'
    changeOrigin: true
  '/grafana/api':
    target: 'http://grafana:3000/api'
    changeOrigin: true

techdocs:
  builder: 'local'
  generator:
    runIn: 'docker'
  publisher:
    type: 'local'

auth:
  environment: development
  providers:
    github:
      development:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}

scaffolder:
  defaultAuthor:
    name: Platform Team
    email: platform@company.com
  defaultCommitMessage: 'Initial commit from platform template'

catalog:
  import:
    entityFilename: catalog-info.yaml
    pullRequestBranchName: backstage-integration
  rules:
    - allow: [Component, System, API, Resource, Location]
  locations:
    # Locations
    - type: file
      target: ../../catalog/locations.yaml
    # Templates
    - type: file
      target: ../../templates/*/template.yaml
      rules:
        - allow: [Template]
```

### 2. Software Templates

#### Microservice Template
```yaml
# templates/microservice/template.yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: microservice-template
  title: Create a New Microservice
  description: Bootstrap a new microservice with best practices
  tags:
    - recommended
    - microservice
spec:
  owner: platform-team
  type: service
  
  parameters:
    - title: Service Information
      required:
        - serviceName
        - description
        - owner
      properties:
        serviceName:
          title: Service Name
          type: string
          description: Unique name for the service
          pattern: '^[a-z0-9-]+$'
        description:
          title: Description
          type: string
          description: What does this service do?
        owner:
          title: Owner
          type: string
          description: Team owning this service
          ui:field: OwnerPicker
          ui:options:
            allowedKinds:
              - Group
    
    - title: Technology Stack
      required:
        - language
        - database
      properties:
        language:
          title: Programming Language
          type: string
          enum:
            - nodejs
            - python
            - java
            - go
          enumNames:
            - Node.js
            - Python
            - Java
            - Go
        database:
          title: Database
          type: string
          enum:
            - postgresql
            - mysql
            - mongodb
            - redis
          enumNames:
            - PostgreSQL
            - MySQL
            - MongoDB
            - Redis
    
    - title: Repository Settings
      required:
        - repoUrl
      properties:
        repoUrl:
          title: Repository Location
          type: string
          ui:field: RepoUrlPicker
          ui:options:
            allowedHosts:
              - github.com
              - gitlab.com

  steps:
    - id: fetch
      name: Fetch Template
      action: fetch:template
      input:
        url: ./skeleton
        values:
          serviceName: ${{ parameters.serviceName }}
          description: ${{ parameters.description }}
          owner: ${{ parameters.owner }}
          language: ${{ parameters.language }}
          database: ${{ parameters.database }}
    
    - id: publish
      name: Publish to GitHub
      action: publish:github
      input:
        allowedHosts: ['github.com']
        description: ${{ parameters.description }}
        repoUrl: ${{ parameters.repoUrl }}
        defaultBranch: main
        repoVisibility: private
    
    - id: register
      name: Register Component
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps.publish.output.repoContentsUrl }}
        catalogInfoPath: '/catalog-info.yaml'
    
    - id: create-pipeline
      name: Create CI/CD Pipeline
      action: github:actions:create
      input:
        repoUrl: ${{ parameters.repoUrl }}
        workflowId: ci-cd
        token: ${{ secrets.GITHUB_TOKEN }}

  output:
    links:
      - title: Repository
        url: ${{ steps.publish.output.remoteUrl }}
      - title: Open in catalog
        icon: catalog
        entityRef: ${{ steps.register.output.entityRef }}
```

### 3. Service Catalog Entity

```yaml
# catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: user-service
  description: User authentication and management service
  annotations:
    github.com/project-slug: myorg/user-service
    backstage.io/techdocs-ref: dir:.
    prometheus.io/rule: user_service_*
    grafana/dashboard-selector: tag:user-service
    pagerduty.com/integration-key: USER_SERVICE_KEY
    sonarqube.org/project-key: user-service
  tags:
    - nodejs
    - authentication
    - microservice
  links:
    - url: https://dashboard.example.com/user-service
      title: Metrics Dashboard
      icon: dashboard
    - url: https://wiki.example.com/user-service
      title: Documentation
      icon: docs
spec:
  type: service
  lifecycle: production
  owner: backend-team
  system: authentication
  dependsOn:
    - resource:postgresql
    - component:email-service
  providesApis:
    - user-api
  consumesApis:
    - email-api
---
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: user-api
  description: User management API
spec:
  type: openapi
  lifecycle: production
  owner: backend-team
  system: authentication
  definition:
    $text: https://github.com/myorg/user-service/blob/main/api/openapi.yaml
---
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: user-database
  description: PostgreSQL database for user service
spec:
  type: database
  owner: backend-team
  system: authentication
```

### 4. Self-Service Actions

```typescript
// plugins/scaffolder-backend/src/actions/create-namespace.ts
import { createTemplateAction } from '@backstage/plugin-scaffolder-node';

export const createNamespaceAction = () => {
  return createTemplateAction({
    id: 'kubernetes:create:namespace',
    schema: {
      input: {
        type: 'object',
        required: ['name'],
        properties: {
          name: {
            type: 'string',
            title: 'Namespace name',
          },
          labels: {
            type: 'object',
            title: 'Labels',
          },
        },
      },
    },
    async handler(ctx) {
      const { name, labels } = ctx.input;
      
      // Kubernetes client logic
      const k8sApi = makeK8sClient();
      
      await k8sApi.createNamespace({
        metadata: {
          name,
          labels: {
            'managed-by': 'backstage',
            ...labels,
          },
        },
      });
      
      ctx.logger.info(`Created namespace ${name}`);
    },
  });
};
```

### 5. Golden Paths

```yaml
# templates/golden-path/template.yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: golden-path-service
  title: Golden Path - Production-Ready Service
  description: Create a fully configured production-ready microservice
spec:
  owner: platform-team
  type: service
  
  parameters:
    - title: Basic Information
      properties:
        serviceName:
          title: Service Name
          type: string
        team:
          title: Owning Team
          type: string
          ui:field: OwnerPicker

  steps:
    - id: create-repo
      name: Create Repository
      action: publish:github
      
    - id: setup-cicd
      name: Configure CI/CD
      action: github:actions:create
      
    - id: create-namespace
      name: Create Kubernetes Namespace
      action: kubernetes:create:namespace
      
    - id: setup-monitoring
      name: Configure Monitoring
      action: prometheus:create:servicemonitor
      
    - id: setup-logging
      name: Configure Logging
      action: loki:create:config
      
    - id: create-dashboards
      name: Create Grafana Dashboards
      action: grafana:create:dashboard
      
    - id: setup-alerts
      name: Configure Alerts
      action: prometheus:create:alerts
      
    - id: register-catalog
      name: Register in Service Catalog
      action: catalog:register
```

### 6. TechDocs Configuration

```yaml
# mkdocs.yml
site_name: 'User Service Documentation'
site_description: 'Technical documentation for User Service'

nav:
  - Home: index.md
  - Getting Started:
    - Quick Start: getting-started/quickstart.md
    - Development Setup: getting-started/dev-setup.md
  - Architecture:
    - Overview: architecture/overview.md
    - API Design: architecture/api.md
    - Database Schema: architecture/database.md
  - Operations:
    - Deployment: operations/deployment.md
    - Monitoring: operations/monitoring.md
    - Troubleshooting: operations/troubleshooting.md
  - Contributing: contributing.md

plugins:
  - techdocs-core

theme:
  name: material
  palette:
    primary: indigo
```

### 7. Plugin Integration Examples

```typescript
// packages/app/src/components/catalog/EntityPage.tsx
import { EntityLayout } from '@backstage/plugin-catalog';
import { EntityKubernetesContent } from '@backstage/plugin-kubernetes';
import { EntityPrometheusContent } from '@roadiehq/backstage-plugin-prometheus';
import { EntityGrafanaDashboardsCard } from '@k-phoen/backstage-plugin-grafana';

const serviceEntityPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3}>
        <Grid item md={6}>
          <EntityAboutCard />
        </Grid>
        <Grid item md={6}>
          <EntityLinksCard />
        </Grid>
        <Grid item md={12}>
          <EntityPrometheusContent />
        </Grid>
      </Grid>
    </EntityLayout.Route>
    
    <EntityLayout.Route path="/kubernetes" title="Kubernetes">
      <EntityKubernetesContent />
    </EntityLayout.Route>
    
    <EntityLayout.Route path="/ci-cd" title="CI/CD">
      <EntityGithubActionsContent />
    </EntityLayout.Route>
    
    <EntityLayout.Route path="/monitoring" title="Monitoring">
      <Grid container>
        <Grid item md={12}>
          <EntityGrafanaDashboardsCard />
        </Grid>
      </Grid>
    </EntityLayout.Route>
  </EntityLayout>
);
```
