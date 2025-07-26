# GitHub Container Registry (ghcr.io) Documentation

## Overview
GitHub Container Registry (GHCR) is a container registry service that allows you to host and manage Docker container images directly within GitHub. It integrates seamlessly with GitHub repositories and Actions.

## Key Features
- Native GitHub integration
- Fine-grained permissions
- Free for public images
- Supports Docker and OCI image formats
- Multi-architecture image support
- 10GB layer size limit

## Authentication

### Personal Access Token (PAT)
```bash
# Create PAT with packages permissions:
# - read:packages
# - write:packages  
# - delete:packages (optional)

# Login with PAT
echo $PAT | docker login ghcr.io -u USERNAME --password-stdin
```

### GitHub Actions
```yaml
# Using GITHUB_TOKEN (automatic)
- name: Login to GitHub Container Registry
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

## Image Naming Convention

### Format
```
ghcr.io/NAMESPACE/IMAGE_NAME:TAG
```

### Examples
```bash
# Personal account
ghcr.io/username/my-app:latest

# Organization
ghcr.io/my-org/backend-service:v1.2.3

# Repository packages
ghcr.io/owner/repo/component:main
```

## Pushing Images

### Basic Push
```bash
# Build image
docker build -t my-app:latest .

# Tag for GHCR
docker tag my-app:latest ghcr.io/username/my-app:latest

# Push to registry
docker push ghcr.io/username/my-app:latest
```

### Multi-tag Push
```bash
# Tag multiple versions
docker tag my-app:latest ghcr.io/username/my-app:latest
docker tag my-app:latest ghcr.io/username/my-app:1.0.0
docker tag my-app:latest ghcr.io/username/my-app:stable

# Push all tags
docker push ghcr.io/username/my-app --all-tags
```

## Pulling Images

### Public Images
```bash
# No authentication needed
docker pull ghcr.io/owner/public-image:latest
```

### Private Images
```bash
# Login first
docker login ghcr.io -u USERNAME

# Pull image
docker pull ghcr.io/owner/private-image:latest
```

### Pull by Digest
```bash
# More secure - ensures exact image
docker pull ghcr.io/owner/image@sha256:abc123...
```

## GitHub Actions Integration

### Complete Workflow
```yaml
name: Build and Push

on:
  push:
    branches: [main]
    tags: ['v*']

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Setup Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Login to GHCR
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=semver,pattern={{version}}
          type=semver,pattern={{major}}.{{minor}}
          type=raw,value=latest,enable={{is_default_branch}}

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

### Multi-Registry Push
```yaml
- name: Login to Docker Hub
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKERHUB_USERNAME }}
    password: ${{ secrets.DOCKERHUB_TOKEN }}

- name: Login to GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}

- name: Build and push to multiple registries
  uses: docker/build-push-action@v5
  with:
    push: true
    tags: |
      docker.io/username/app:latest
      ghcr.io/username/app:latest
```

## Permissions and Access Control

### Package Permissions
```yaml
# Repository-level permissions
permissions:
  contents: read
  packages: write
```

### Visibility Settings
```bash
# Make package public (via GitHub UI or API)
gh api \
  --method PATCH \
  -H "Accept: application/vnd.github+json" \
  /user/packages/container/IMAGE_NAME/versions/VERSION_ID \
  -f visibility='public'
```

### Linking to Repository
```dockerfile
# Add labels to link image to repository
LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO"
LABEL org.opencontainers.image.description="My application"
LABEL org.opencontainers.image.licenses="MIT"
```

## Image Management

### List Images
```bash
# Using GitHub CLI
gh api /user/packages?package_type=container

# For organization
gh api /orgs/ORG_NAME/packages?package_type=container
```

### Delete Images
```bash
# Delete specific version
gh api \
  --method DELETE \
  -H "Accept: application/vnd.github+json" \
  /user/packages/container/IMAGE_NAME/versions/VERSION_ID

# Delete entire package
gh api \
  --method DELETE \
  -H "Accept: application/vnd.github+json" \
  /user/packages/container/IMAGE_NAME
```

## Best Practices

### 1. Use Semantic Versioning
```yaml
tags: |
  type=semver,pattern={{version}}
  type=semver,pattern={{major}}.{{minor}}
  type=semver,pattern={{major}}
```

### 2. Add Metadata Labels
```dockerfile
LABEL org.opencontainers.image.title="My App"
LABEL org.opencontainers.image.description="Application description"
LABEL org.opencontainers.image.url="https://github.com/owner/repo"
LABEL org.opencontainers.image.source="https://github.com/owner/repo"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.created="2023-01-01T00:00:00Z"
LABEL org.opencontainers.image.licenses="MIT"
```

### 3. Multi-Architecture Support
```yaml
- name: Set up QEMU
  uses: docker/setup-qemu-action@v3

- name: Build multi-arch
  uses: docker/build-push-action@v5
  with:
    platforms: linux/amd64,linux/arm64,linux/arm/v7
```

### 4. Cache Management
```yaml
# Use GitHub Actions cache
cache-from: type=gha
cache-to: type=gha,mode=max

# Or use registry cache
cache-from: type=registry,ref=ghcr.io/user/app:buildcache
cache-to: type=registry,ref=ghcr.io/user/app:buildcache,mode=max
```

### 5. Security Scanning
```yaml
- name: Run Trivy scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
    format: 'sarif'
    output: 'trivy-results.sarif'

- name: Upload results
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```

## Advanced Usage

### Conditional Push
```yaml
- name: Build and conditionally push
  uses: docker/build-push-action@v5
  with:
    push: ${{ github.event_name != 'pull_request' }}
    tags: ghcr.io/${{ github.repository }}:latest
```

### Retention Policy
```yaml
# Using GitHub's retention policy API
- name: Delete old images
  uses: actions/delete-package-versions@v4
  with:
    package-name: 'my-app'
    package-type: 'container'
    min-versions-to-keep: 10
    delete-only-pre-release-versions: true
```

### Migration from Docker Hub
```bash
# Pull from Docker Hub
docker pull username/image:tag

# Retag for GHCR
docker tag username/image:tag ghcr.io/username/image:tag

# Push to GHCR
docker push ghcr.io/username/image:tag
```

## Troubleshooting

### Common Issues

#### 1. Authentication Failed
```bash
# Verify token permissions
gh auth status

# Re-authenticate
gh auth login

# Check token scopes
gh api user -H "Accept: application/vnd.github+json"
```

#### 2. Permission Denied
```yaml
# Ensure workflow has correct permissions
permissions:
  contents: read
  packages: write
```

#### 3. Image Not Found
```bash
# Check visibility settings
# Private images require authentication
docker login ghcr.io -u USERNAME
```

#### 4. Rate Limiting
```bash
# Check rate limit status
gh api rate_limit
```

### Debug Commands
```bash
# Inspect image locally
docker inspect ghcr.io/owner/image:tag

# Get manifest
docker manifest inspect ghcr.io/owner/image:tag

# Check registry catalog (requires auth)
curl -H "Authorization: Bearer TOKEN" \
  https://ghcr.io/v2/_catalog
```

## Cost Considerations

### Free Tier
- Public repositories: Unlimited
- Private repositories: 
  - 500MB storage
  - 1GB transfer/month

### Optimization Tips
1. Use multi-stage builds to reduce image size
2. Clean up old versions regularly
3. Use `.dockerignore` to exclude unnecessary files
4. Compress layers where possible

## Integration Examples

### Docker Compose
```yaml
version: '3.8'
services:
  app:
    image: ghcr.io/username/my-app:latest
    environment:
      - NODE_ENV=production
```

### Kubernetes
```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: app
        image: ghcr.io/username/my-app:latest
      imagePullSecrets:
      - name: ghcr-secret
```

### Create Kubernetes Secret
```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=USERNAME \
  --docker-password=PAT_TOKEN
```