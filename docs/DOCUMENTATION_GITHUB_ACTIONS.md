# GitHub Actions Documentation

## Overview
GitHub Actions enables automation of software workflows directly in your GitHub repository. This document covers essential patterns and best practices for CI/CD pipelines.

## Workflow Syntax

### Basic Structure
```yaml
name: Workflow Name
on: [push, pull_request]
jobs:
  job-name:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run a command
        run: echo "Hello World"
```

### Event Triggers

#### Common Triggers
```yaml
on:
  push:
    branches: [main, develop]
    tags: ['v*']
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight
  workflow_dispatch:  # Manual trigger
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        type: choice
        options: [staging, production]
```

## Job Configuration

### Runner Selection
```yaml
jobs:
  test:
    runs-on: ubuntu-latest  # GitHub-hosted runner
    # Alternative: runs-on: self-hosted
```

### Matrix Builds
```yaml
strategy:
  fail-fast: false
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
    node-version: [14, 16, 18]
    exclude:
      - os: macos-latest
        node-version: 14
```

### Job Dependencies
```yaml
jobs:
  build:
    runs-on: ubuntu-latest
  test:
    needs: build
    runs-on: ubuntu-latest
  deploy:
    needs: [build, test]
    if: github.ref == 'refs/heads/main'
```

## Permissions and Security

### Repository Permissions
```yaml
permissions:
  contents: read
  packages: write
  security-events: write
  pull-requests: write
```

### Secrets vs Variables
- **Secrets**: Encrypted, not shown in logs
  ```yaml
  env:
    API_KEY: ${{ secrets.API_KEY }}
  ```
- **Variables**: Plain text, visible in logs
  ```yaml
  env:
    ENVIRONMENT: ${{ vars.ENVIRONMENT }}
  ```

### Conditional Secret Usage
```yaml
- name: Login to Registry
  if: github.event_name != 'pull_request'
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_TOKEN || secrets.DOCKER_PASSWORD }}
```

## Caching Strategies

### Dependency Caching
```yaml
- name: Cache Node modules
  uses: actions/cache@v4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

### Docker Layer Caching
```yaml
- name: Build Docker image
  uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

## Common Actions

### Essential Actions
```yaml
# Checkout code
- uses: actions/checkout@v4

# Setup languages
- uses: actions/setup-node@v4
  with:
    node-version: 18
    
- uses: r-lib/actions/setup-r@v2
  with:
    r-version: '4.3.1'

# Upload artifacts
- uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: test-results/

# Docker setup
- uses: docker/setup-buildx-action@v3
- uses: docker/login-action@v3
```

## Error Handling

### Continue on Error
```yaml
- name: Run tests
  continue-on-error: true
  run: npm test
```

### Timeout Control
```yaml
- name: Long running task
  timeout-minutes: 30
  run: ./long-script.sh
```

### Error Outputs
```yaml
- name: Check status
  id: check
  run: |
    if [[ -f "error.log" ]]; then
      echo "error=true" >> $GITHUB_OUTPUT
    fi
    
- name: Handle error
  if: steps.check.outputs.error == 'true'
  run: echo "Error detected"
```

## Environment Management

### Environment Variables
```yaml
env:
  GLOBAL_VAR: value

jobs:
  test:
    env:
      JOB_VAR: value
    steps:
      - name: Step with env
        env:
          STEP_VAR: value
        run: echo $GLOBAL_VAR $JOB_VAR $STEP_VAR
```

### Multi-Environment Deployment
```yaml
deploy:
  strategy:
    matrix:
      environment: [staging, production]
  environment: ${{ matrix.environment }}
  runs-on: ubuntu-latest
```

## Best Practices

### 1. Workflow Organization
- Keep workflows focused on single responsibility
- Use workflow_call for reusable workflows
- Name jobs and steps clearly

### 2. Security
- Never hardcode secrets
- Use least privilege permissions
- Validate inputs in workflow_dispatch

### 3. Performance
- Use matrix builds wisely
- Cache dependencies aggressively
- Parallelize independent jobs

### 4. Reliability
- Set appropriate timeouts
- Use continue-on-error for non-critical steps
- Implement retry logic for flaky operations

### 5. Debugging
```yaml
- name: Debug context
  env:
    GITHUB_CONTEXT: ${{ toJson(github) }}
  run: echo "$GITHUB_CONTEXT"
```

## Advanced Patterns

### Composite Actions
```yaml
# .github/actions/setup-project/action.yml
name: Setup Project
runs:
  using: composite
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
    - run: npm ci
      shell: bash
```

### Conditional Execution
```yaml
- name: Deploy to production
  if: |
    github.event_name == 'push' &&
    github.ref == 'refs/heads/main' &&
    contains(github.event.head_commit.message, '[deploy]')
```

### Output Sharing
```yaml
- name: Generate version
  id: version
  run: echo "version=1.2.3" >> $GITHUB_OUTPUT
  
- name: Use version
  run: echo "Version is ${{ steps.version.outputs.version }}"
```

## Troubleshooting

### Common Issues
1. **Permission Denied**: Check repository settings and PAT scopes
2. **Secret Not Found**: Verify secret exists in correct environment
3. **Workflow Not Triggering**: Check branch protection rules
4. **Cache Miss**: Verify cache key includes all dependencies

### Debug Mode
```yaml
- name: Enable debug logging
  run: |
    echo "ACTIONS_STEP_DEBUG=true" >> $GITHUB_ENV
    echo "ACTIONS_RUNNER_DEBUG=true" >> $GITHUB_ENV
```