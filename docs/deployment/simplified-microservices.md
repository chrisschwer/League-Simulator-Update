# Simplified Microservices for MVP

A middle-ground approach that maintains separation of concerns while drastically simplifying the infrastructure for a hobbyist/MVP project.

> **Note**: This is an alternative to the [Simple Monolithic](simple-monolithic.md) approach. For most use cases, the monolithic version is recommended.

## Overview

This approach splits the application into just two services:
- **Simulator**: Runs the daily simulations
- **Web App**: Serves the Shiny interface (optional if using ShinyApps.io)

## Architecture

```
┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │
│   Simulator     │────▶│   Shared Data   │
│   Service       │     │   Volume        │
│                 │     │                 │
└─────────────────┘     └────────┬────────┘
                                 │
                        ┌────────▼────────┐
                        │                 │
                        │   Shiny App     │
                        │   (Optional)    │
                        │                 │
                        └─────────────────┘
```

## Implementation

### Docker Compose

```yaml
version: '3'

services:
  simulator:
    build:
      context: .
      dockerfile: Dockerfile.simple
    environment:
      - RAPIDAPI_KEY=${RAPIDAPI_KEY}
      - SHINYAPPS_IO_SECRET=${SHINYAPPS_IO_SECRET}
      - SEASON=${SEASON}
    volumes:
      - simulation-data:/ShinyApp/data
    restart: unless-stopped
    
  shiny:
    image: rocker/shiny:latest
    ports:
      - "3838:3838"
    volumes:
      - ./ShinyApp:/srv/shiny-server/
      - simulation-data:/srv/shiny-server/data:ro
    depends_on:
      - simulator
    profiles:
      - with-shiny  # Only runs when explicitly requested

volumes:
  simulation-data:
```

### Simplified CI/CD

```yaml
# .github/workflows/build-and-push.yml
name: Build and Push

on:
  push:
    branches: [main]
    paths:
      - 'RCode/**'
      - 'ShinyApp/**'
      - 'Dockerfile*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build and push
        run: |
          echo "${{ secrets.DOCKER_PASSWORD }}" | docker login -u ${{ secrets.DOCKER_USERNAME }} --password-stdin
          docker build -f Dockerfile.simple -t ${{ secrets.DOCKER_USERNAME }}/league-simulator:latest .
          docker push ${{ secrets.DOCKER_USERNAME }}/league-simulator:latest
```

No security scanning, no complex deployment pipelines, no Kubernetes manifests.

## Development Workflow

### Local Development

```bash
# Run both services locally
docker-compose up

# Run just the simulator (if using ShinyApps.io)
docker-compose up simulator

# Run with local code mounted for development
docker-compose -f docker-compose.dev.yml up
```

### Development Compose File

```yaml
# docker-compose.dev.yml
version: '3'

services:
  simulator:
    build:
      context: .
      dockerfile: Dockerfile.simple
    environment:
      - RAPIDAPI_KEY=${RAPIDAPI_KEY}
      - SHINYAPPS_IO_SECRET=${SHINYAPPS_IO_SECRET}
    volumes:
      - ./RCode:/RCode  # Mount source code
      - ./ShinyApp:/ShinyApp
    command: ["Rscript", "/RCode/updateSchedulerSimple.R"]
```

## Deployment Options

### Option 1: VPS with Docker Compose

```bash
# On your VPS
git pull
docker-compose pull
docker-compose up -d
```

### Option 2: Manual Docker Commands

```bash
# Pull latest
docker pull chrisschwer/league-simulator:latest

# Run simulator
docker run -d \
  --name simulator \
  -e RAPIDAPI_KEY=$RAPIDAPI_KEY \
  -e SHINYAPPS_IO_SECRET=$SHINYAPPS_IO_SECRET \
  -v simulation-data:/ShinyApp/data \
  chrisschwer/league-simulator:latest
```

### Option 3: Systemd Service

```ini
# /etc/systemd/system/league-simulator.service
[Unit]
Description=League Simulator
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/docker run --rm \
  --name league-simulator \
  -e RAPIDAPI_KEY=${RAPIDAPI_KEY} \
  -e SHINYAPPS_IO_SECRET=${SHINYAPPS_IO_SECRET} \
  chrisschwer/league-simulator:latest
ExecStop=/usr/bin/docker stop league-simulator
Restart=always

[Install]
WantedBy=multi-user.target
```

## Benefits Over Full Microservices

1. **Simpler Infrastructure**
   - No service mesh
   - No complex networking
   - No Kubernetes required

2. **Easier Development**
   - Everything runs with one command
   - Local development mirrors production
   - No inter-service authentication

3. **Lower Operational Overhead**
   - Fewer moving parts
   - Simple logging (just check two services)
   - Easy debugging

4. **Cost Effective**
   - Runs on a single small VPS
   - No cloud provider lock-in
   - Minimal resource requirements

## When to Use This Approach

Choose simplified microservices when:
- You want to keep services separate for clarity
- You might scale individual components later
- You want to deploy Shiny separately from simulation
- You have multiple developers working on different parts

## Migration Path

### From Monolithic

```bash
# Just use the same Dockerfile
docker build -f Dockerfile.simple -t league-simulator:microservices .

# Deploy with new compose file
docker-compose -f docker-compose.microservices.yml up -d
```

### To Full Microservices

When ready to scale:
1. Extract API service from simulator
2. Add message queue for async processing
3. Implement proper service discovery
4. Add monitoring and tracing

## Monitoring

### Simple Health Checks

```yaml
services:
  simulator:
    healthcheck:
      test: ["CMD", "pgrep", "R"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Basic Monitoring

```bash
# Check if services are running
docker-compose ps

# View logs
docker-compose logs -f simulator

# Resource usage
docker stats
```

## Conclusion

This simplified microservices approach provides a stepping stone between monolithic and full microservices architecture. It maintains separation of concerns while avoiding the complexity overhead that often kills MVP projects.

For most hobbyist projects, the [Simple Monolithic](simple-monolithic.md) approach is still recommended as it provides the same functionality with even less complexity.