# CI/CD Pipeline Optimization - Step-by-Step Guide

## Step 1: Analyze Current Pipeline Performance

### 1.1 Measure Baseline Metrics
```bash
# GitHub Actions - analyze workflow runs
gh run list --workflow=ci.yml --limit=50 --json conclusion,startedAt,updatedAt > runs.json

# Calculate average duration
cat runs.json | jq '[.[] | ((.updatedAt | fromdateiso8601) - (.startedAt | fromdateiso8601))] | add/length'
```

### 1.2 Identify Bottlenecks
- Review each job duration
- Identify sequential vs parallel jobs
- Check dependency installation times
- Analyze test execution times

## Step 2: Implement Caching Strategies

### 2.1 Cache Dependencies
```yaml
# npm/yarn caching
- uses: actions/setup-node@v4
  with:
    node-version: '18'
    cache: 'npm'  # or 'yarn'

# pip caching
- uses: actions/setup-python@v5
  with:
    python-version: '3.11'
    cache: 'pip'

# Gradle caching
- uses: actions/setup-java@v4
  with:
    java-version: '17'
    distribution: 'temurin'
    cache: 'gradle'
```

### 2.2 Cache Build Artifacts
```yaml
- name: Cache build output
  uses: actions/cache@v3
  with:
    path: |
      dist/
      build/
      .next/cache
    key: ${{ runner.os }}-build-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-build-
```

### 2.3 Docker Layer Caching
```yaml
- name: Build with cache
  uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

## Step 3: Parallelize Jobs

### 3.1 Split Test Suites
```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        shard: [1, 2, 3, 4]
    steps:
      - run: npm test -- --shard=${{ matrix.shard }}/4
```

### 3.2 Matrix Strategy for Multi-Environment
```yaml
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        node: [16, 18, 20]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
```

## Step 4: Optimize Docker Builds

### 4.1 Multi-Stage Dockerfile
```dockerfile
# Build stage
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# Production stage
FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package.json ./
USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

### 4.2 Use BuildKit
```bash
export DOCKER_BUILDKIT=1
docker build --build-arg BUILDKIT_INLINE_CACHE=1 \
  --cache-from myapp:latest \
  -t myapp:new .
```

### 4.3 Minimize Layers
```dockerfile
# Bad - Multiple layers
RUN npm install
RUN npm run build
RUN npm prune --production

# Good - Single layer
RUN npm install && npm run build && npm prune --production
```

## Step 5: Implement Smart Test Execution

### 5.1 Run Only Changed Tests
```bash
# Jest
npm test -- --onlyChanged --changedSince=origin/main

# pytest
pytest --testmon --testmon-noselect
```

### 5.2 Fail Fast Strategy
```yaml
strategy:
  fail-fast: true
  matrix:
    node: [16, 18, 20]
```

### 5.3 Code Coverage Optimization
```bash
# Only run coverage on main branch
if [ "$GITHUB_REF" == "refs/heads/main" ]; then
  npm test -- --coverage
else
  npm test
fi
```

## Step 6: Optimize Dependency Installation

### 6.1 Use CI-Specific Install
```bash
# npm - use ci for faster, cleaner installs
npm ci --prefer-offline --no-audit

# yarn
yarn install --frozen-lockfile --prefer-offline

# pnpm - fastest option
pnpm install --frozen-lockfile
```

### 6.2 Skip Optional Dependencies
```bash
npm ci --omit=optional --omit=dev
```

## Step 7: Implement Conditional Workflows

### 7.1 Path Filtering
```yaml
on:
  push:
    paths:
      - 'src/**'
      - 'tests/**'
      - 'package.json'
      - '.github/workflows/**'
    paths-ignore:
      - '**.md'
      - 'docs/**'
```

### 7.2 Skip CI for Specific Commits
```yaml
jobs:
  build:
    if: "!contains(github.event.head_commit.message, '[skip ci]')"
```

## Step 8: Use Self-Hosted Runners (Optional)

### 8.1 Set Up Runner
```bash
# Download
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz

# Configure
./config.sh --url https://github.com/OWNER/REPO --token YOUR_TOKEN

# Run
./run.sh
```

### 8.2 Use in Workflow
```yaml
jobs:
  build:
    runs-on: self-hosted
```

## Step 9: Monitor and Alert

### 9.1 Track Metrics
```bash
# Script to track workflow duration
#!/bin/bash
gh api repos/OWNER/REPO/actions/runs \
  --jq '.workflow_runs[] | {id, name, conclusion, duration: (.updated_at | fromdateiso8601) - (.created_at | fromdateiso8601)}' \
  > workflow_metrics.json
```

### 9.2 Set Up Alerts
```yaml
- name: Notify on failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Pipeline failed: ${{ github.repository }}",
        "blocks": [{
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "Pipeline *${{ github.workflow }}* failed\n*Repository:* ${{ github.repository }}\n*Branch:* ${{ github.ref }}"
          }
        }]
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

## Step 10: Continuous Optimization

### 10.1 Regular Reviews
- Monthly pipeline performance review
- Identify new bottlenecks
- Update dependencies and actions
- Review and remove unused steps

### 10.2 A/B Testing Optimizations
```yaml
# Test new optimization in feature branch
# Compare metrics before merging
```

## Performance Targets

| Metric | Before | Target | Achieved |
|--------|--------|--------|----------|
| Total Pipeline Time | 25min | <10min | __ |
| Unit Tests | 8min | <3min | __ |
| Build Time | 12min | <5min | __ |
| Deploy Time | 5min | <2min | __ |

## Cost Optimization

### Reduce GitHub Actions Minutes
1. Use concurrency limits
2. Skip unnecessary jobs
3. Optimize runner selection
4. Consider self-hosted runners for heavy workloads

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```
