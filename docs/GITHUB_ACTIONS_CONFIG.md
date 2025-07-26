# GitHub Actions Configuration Guide

This document provides configuration instructions for setting up GitHub Actions workflows in the League Simulator project.

## Required Repository Settings

### 1. Repository Secrets

The following secrets must be configured in your repository settings (Settings → Secrets and variables → Actions → Secrets):

| Secret Name | Description | Required | Example |
|------------|-------------|----------|---------|
| `RAPIDAPI_KEY` | API key for accessing football data via RapidAPI | Yes | `abc123def456...` |
| `SHINYAPPS_IO_SECRET` | Secret for deploying to shinyapps.io | Optional | `xyz789...` |
| `SHINYAPPS_IO_TOKEN` | Token for shinyapps.io deployment | Optional | `token123...` |
| `SHINYAPPS_IO_NAME` | Username for shinyapps.io | Optional | `yourusername` |
| `DOCKERHUB_TOKEN` | Docker Hub access token for pushing images | Optional | `dckr_pat_...` |
| `DOCKERHUB_USERNAME` | Docker Hub username (deprecated - use variables) | No | Use repository variables instead |
| `CODECOV_TOKEN` | Token for uploading coverage reports to Codecov | Optional | `codecov123...` |

### 2. Repository Variables

The following variables should be configured (Settings → Secrets and variables → Actions → Variables):

| Variable Name | Description | Required | Example |
|--------------|-------------|----------|---------|
| `DOCKERHUB_USERNAME` | Docker Hub username for image registry | Optional | `myusername` |

### 3. Environments

For production deployments, create an environment named `production` with appropriate protection rules:
- Required reviewers (optional)
- Deployment branches: Only from `main`
- Wait timer (optional)

## Workflow Files Overview

### 1. R-tests.yml
**Purpose**: Runs comprehensive R tests across multiple OS and R versions

**Key Features**:
- Matrix testing (Ubuntu/macOS, R 4.2/4.3/4.4)
- Test failure threshold (currently 40 failures allowed)
- Coverage reporting (optional)
- Performance tests for specific configurations

**Configuration Notes**:
- Tests will pass with up to 40 failures (temporary while fixing tests)
- Coverage analysis is non-blocking
- Performance tests only run on Ubuntu with R 4.4.0

### 2. automated-review.yml
**Purpose**: Provides automated PR review feedback

**Key Features**:
- PR size analysis
- R code linting
- Security checks for common vulnerabilities
- Documentation update detection

**Configuration Notes**:
- All checks are non-blocking (continue-on-error)
- Requires GitHub token (automatically provided)

### 3. build-test-deploy.yml
**Purpose**: Build, test, and deploy Docker images

**Key Features**:
- Multi-platform builds (amd64/arm64)
- Container structure tests
- Security scanning with Trivy
- Automated release creation for tags

**Configuration Notes**:
- Docker Hub credentials optional (builds will succeed without push)
- Uses repository variables for Docker Hub username
- Deployment bundle created for tagged releases

### 4. deployment-safety-tests.yml
**Purpose**: Comprehensive deployment validation

**Key Features**:
- Pre-deployment validation
- Security compliance scanning
- Performance baseline checks
- Deployment simulation

**Configuration Notes**:
- Most tests are non-blocking in CI
- API tests skip when using test credentials
- Performance tests are optional

### 5. deployment-stages.yml
**Purpose**: Staged deployment workflow (called by other workflows)

**Key Features**:
- 5-stage progressive rollout
- Automated rollback on failure
- Canary deployment support
- Manual approval gates

**Configuration Notes**:
- Requires environment configuration
- Called via workflow_call trigger

## Setting Up for Your Repository

### Quick Start

1. **Fork or clone the repository**

2. **Add minimum required secrets**:
   ```bash
   # Required for API functionality
   gh secret set RAPIDAPI_KEY -b "your_api_key_here"
   ```

3. **Optional: Add Docker Hub credentials**:
   ```bash
   # For pushing Docker images
   gh secret set DOCKERHUB_TOKEN -b "your_docker_token"
   gh variable set DOCKERHUB_USERNAME -b "your_username"
   ```

4. **Optional: Add deployment credentials**:
   ```bash
   # For shinyapps.io deployment
   gh secret set SHINYAPPS_IO_SECRET -b "your_secret"
   gh secret set SHINYAPPS_IO_TOKEN -b "your_token"
   gh secret set SHINYAPPS_IO_NAME -b "your_username"
   ```

### Running Workflows

- **On push**: Workflows automatically run on push to main/develop
- **On PR**: Automated review and tests run on all PRs
- **Manual trigger**: Use workflow_dispatch for manual runs
- **Tagged releases**: Create a tag starting with 'v' to trigger deployment

## Troubleshooting

### Common Issues

1. **"Test execution failed"**
   - Check if RAPIDAPI_KEY is set
   - Verify test dependencies are installed
   - Review test logs for specific failures

2. **"Docker push failed"**
   - Ensure Docker Hub credentials are configured
   - Check if DOCKERHUB_USERNAME variable is set
   - Verify token has push permissions

3. **"Security scan failed"**
   - Review Trivy output for vulnerabilities
   - Update base images if needed
   - Consider adding security exceptions for false positives

4. **"Coverage analysis failed"**
   - This is non-blocking and can be ignored
   - Ensure covr package is installed
   - Check for C++ compilation issues

### Viewing Logs

```bash
# List recent workflow runs
gh run list

# View specific run details
gh run view [run-id]

# Download artifacts
gh run download [run-id]
```

## Best Practices

1. **Keep secrets secure**: Never commit secrets to the repository
2. **Use environments**: Configure production environment with protection rules
3. **Monitor usage**: Check Actions usage to avoid hitting limits
4. **Cache dependencies**: Workflows use caching to speed up builds
5. **Test locally first**: Use act or similar tools to test workflows locally

## CI/CD Pipeline Flow

```
Push/PR → R Tests → Linting → Build Images → Security Scan → Deploy (if tagged)
           ↓
      Automated Review
           ↓
      Test Results
```

## Maintenance

- **Update R versions**: Modify matrix in R-tests.yml
- **Add new tests**: Place in tests/testthat/ directory
- **Update dependencies**: Modify packagelist.txt and test_packagelist.txt
- **Adjust thresholds**: Update max_allowed_failures in R-tests.yml

## Support

For issues with GitHub Actions:
1. Check workflow logs for detailed error messages
2. Ensure all required secrets and variables are configured
3. Verify file permissions and paths
4. Consult GitHub Actions documentation