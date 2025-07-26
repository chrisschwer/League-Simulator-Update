# Docker Documentation

## Overview
Docker enables containerization of applications, ensuring consistency across different environments. This document covers essential Dockerfile syntax, multi-stage builds, and optimization techniques.

## Dockerfile Instructions

### Essential Instructions

#### FROM - Base Image
```dockerfile
FROM ubuntu:22.04
FROM node:18-alpine AS builder
FROM scratch  # Empty base image
```

#### RUN - Execute Commands
```dockerfile
# Shell form (runs in /bin/sh -c)
RUN apt-get update && apt-get install -y curl

# Exec form (preferred for better signal handling)
RUN ["apt-get", "update"]
RUN ["apt-get", "install", "-y", "curl"]

# Chaining commands to reduce layers
RUN apt-get update && \
    apt-get install -y \
    curl \
    git \
    vim && \
    rm -rf /var/lib/apt/lists/*
```

#### COPY vs ADD
```dockerfile
# COPY - Preferred for files/directories
COPY package.json package-lock.json ./
COPY src/ /app/src/
COPY --chown=user:group file.txt /data/

# ADD - Adds extra features (URL download, tar extraction)
ADD https://example.com/file.tar.gz /tmp/
ADD archive.tar.gz /data/  # Auto-extracts
```

#### Working Directory and User
```dockerfile
WORKDIR /app  # Creates directory if not exists
USER appuser  # Switch to non-root user
```

#### Environment Variables
```dockerfile
ENV NODE_ENV=production
ENV PATH="/app/bin:${PATH}"
ARG BUILD_VERSION=latest  # Build-time only
```

#### Ports and Volumes
```dockerfile
EXPOSE 8080 443  # Documentation only
VOLUME ["/data", "/logs"]  # Creates mount points
```

#### Entry Points and Commands
```dockerfile
# ENTRYPOINT - Main executable
ENTRYPOINT ["python"]
CMD ["app.py"]  # Default arguments

# Or combined
ENTRYPOINT ["python", "app.py"]
CMD ["--port", "8080"]  # Overridable defaults
```

## Multi-Stage Builds

### Basic Pattern
```dockerfile
# Build stage
FROM golang:1.19 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o myapp

# Runtime stage
FROM alpine:3.17
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/myapp /usr/local/bin/
ENTRYPOINT ["myapp"]
```

### Advanced Multi-Stage
```dockerfile
# Dependencies stage
FROM node:18 AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Build stage
FROM node:18 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Runtime stage
FROM node:18-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

## Layer Caching Optimization

### Order Matters
```dockerfile
# Bad - Invalidates cache frequently
COPY . .
RUN npm install

# Good - Leverages cache
COPY package*.json ./
RUN npm install
COPY . .
```

### Cache Mounting (BuildKit)
```dockerfile
# Cache package manager downloads
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Cache apt packages
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y git
```

## Security Best Practices

### Non-Root User
```dockerfile
# Create user during build
RUN useradd -m -u 1000 -s /bin/bash appuser

# Switch to user
USER appuser

# Or in one line
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER 1000
```

### Minimal Base Images
```dockerfile
# Instead of ubuntu:latest (large)
FROM alpine:3.17  # Small Linux

# For static binaries
FROM scratch

# Distroless images
FROM gcr.io/distroless/java:11
```

### Secret Handling
```dockerfile
# Build secrets (not stored in image)
RUN --mount=type=secret,id=npm,target=/root/.npmrc \
    npm install

# Runtime secrets via environment
ENV API_KEY_FILE=/run/secrets/api_key
```

## Health Checks

```dockerfile
# Basic health check
HEALTHCHECK CMD curl -f http://localhost:8080/health || exit 1

# Advanced health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js

# Custom health check script
COPY healthcheck.sh /usr/local/bin/
HEALTHCHECK CMD /usr/local/bin/healthcheck.sh
```

## Volume Management

### Anonymous Volumes
```dockerfile
VOLUME /data  # Creates anonymous volume
```

### Named Volumes (docker-compose.yml)
```yaml
services:
  app:
    volumes:
      - app-data:/data
volumes:
  app-data:
```

### Bind Mounts (Development)
```bash
docker run -v $(pwd)/src:/app/src myapp
```

## Build Arguments

```dockerfile
ARG PYTHON_VERSION=3.11
FROM python:${PYTHON_VERSION}

ARG BUILD_DATE
ARG VCS_REF
LABEL build-date=$BUILD_DATE \
      vcs-ref=$VCS_REF
```

## Image Optimization Techniques

### 1. Minimize Layers
```dockerfile
# Bad - Multiple RUN commands
RUN apt-get update
RUN apt-get install -y curl
RUN apt-get install -y git

# Good - Single RUN command
RUN apt-get update && \
    apt-get install -y curl git && \
    rm -rf /var/lib/apt/lists/*
```

### 2. Clean Up In Same Layer
```dockerfile
RUN apt-get update && \
    apt-get install -y build-essential && \
    make && \
    apt-get purge -y build-essential && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*
```

### 3. Use .dockerignore
```
# .dockerignore
node_modules
.git
.env
*.log
dist
.DS_Store
```

### 4. Leverage Build Cache
```dockerfile
# Copy dependency files first
COPY requirements.txt .
RUN pip install -r requirements.txt

# Then copy source code
COPY src/ ./src/
```

## Docker Compose Patterns

### Basic Service Definition
```yaml
version: '3.8'
services:
  web:
    build: .
    ports:
      - "8080:8080"
    environment:
      - NODE_ENV=production
    depends_on:
      - db
  
  db:
    image: postgres:15
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: secret

volumes:
  db-data:
```

### Advanced Compose Features
```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.prod
      args:
        BUILD_VERSION: ${VERSION:-latest}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - frontend
      - backend

networks:
  frontend:
  backend:
```

## Best Practices Summary

1. **Start with minimal base images**
2. **Run as non-root user**
3. **Use multi-stage builds**
4. **Order Dockerfile commands for cache efficiency**
5. **Clean up in the same RUN statement**
6. **Use .dockerignore**
7. **Don't store secrets in images**
8. **Set appropriate health checks**
9. **Use specific image tags, not latest**
10. **Label images with metadata**

## Common Patterns

### Python Application
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
USER nobody
CMD ["python", "app.py"]
```

### Node.js Application
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
USER node
EXPOSE 3000
CMD ["node", "server.js"]
```

### Static Website
```dockerfile
FROM node:18 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
```