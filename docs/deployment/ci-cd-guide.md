# CI/CD Guide for League Simulator

## Overview

This guide covers the CI/CD pipeline implementation for the League Simulator project, including test automation, deployment strategies, and the reliability improvements introduced in issue #61.

## Pipeline Architecture

### Core Components

1. **Test Automation**
   - Parallel test execution
   - Incremental testing
   - Flaky test management
   - Performance monitoring

2. **Build Optimization**
   - Docker layer caching
   - Dependency caching
   - Multi-stage builds
   - Resource management

3. **Deployment Safety**
   - Automated rollback
   - Health checks
   - Gradual rollout
   - Monitoring integration

## Test Automation

### Parallel Test Execution

The test suite is divided into 4 shards for parallel execution:

```yaml
# .github/workflows/parallel-tests.yml
strategy:
  matrix:
    test-shard:
      - { name: "Core", pattern: "test-(prozent|Tabelle|transform)" }
      - { name: "Integration", pattern: "test-(season|elo|configmap)" }
      - { name: "Performance", pattern: "test-performance" }
      - { name: "E2E", pattern: "test-(e2e|integration)" }
```

**Benefits:**
- 4x faster test execution
- Isolated test environments
- Better resource utilization
- Easier debugging

### Incremental Testing

Only tests affected by code changes are executed:

```yaml
# .github/workflows/incremental-tests.yml
- name: Detect test dependencies
  run: |
    Rscript .github/scripts/test-dependencies.R \
      --changed-files "${{ steps.files.outputs.all }}" \
      --output affected-tests.txt
```

**How it works:**
1. Analyze changed files
2. Map dependencies to tests
3. Execute only affected tests
4. Fall back to full suite for major changes

### Retry Mechanisms

Intelligent retry logic with exponential backoff:

```r
# Example retry implementation
retry_with_backoff <- function(fn, max_attempts = 3, initial_delay = 1) {
  for (i in 1:max_attempts) {
    result <- tryCatch(
      { fn() },
      error = function(e) {
        if (i < max_attempts) {
          delay <- initial_delay * (2^(i-1))
          message(sprintf("Attempt %d failed, retrying in %ds...", i, delay))
          Sys.sleep(delay)
          NULL
        } else {
          stop(e)
        }
      }
    )
    if (!is.null(result)) return(result)
  }
}
```

### Flaky Test Management

Automatic detection and quarantine of unstable tests:

```yaml
# .github/workflows/quarantine-flaky-tests.yml
- name: Detect flaky tests
  run: |
    Rscript .github/scripts/flaky-test-detector.R \
      --threshold 0.2 \
      --window 10 \
      --output .github/test-quarantine.json
```

**Quarantine Process:**
1. Test fails >20% in last 10 runs
2. Automatically quarantined
3. Issue created for investigation
4. Excluded from CI until fixed

## Build Optimization

### Docker Layer Caching

Optimized Dockerfile for maximum cache efficiency:

```dockerfile
# Good: Dependencies first (changes rarely)
FROM rocker/r-ver:4.3.3
COPY renv.lock /app/
RUN R -e "renv::restore()"

# Good: Application code last (changes frequently)
COPY . /app/
```

### GitHub Actions Cache

Multiple caching strategies for faster builds:

```yaml
# Package cache
- uses: actions/cache@v3
  with:
    path: ~/.local/share/renv
    key: ${{ runner.os }}-renv-${{ hashFiles('**/renv.lock') }}

# Docker layer cache
- uses: docker/build-push-action@v4
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

### Resource Optimization

Efficient resource allocation:

```yaml
# Workflow-level timeout
timeout-minutes: 30

# Job-level resource hints
runs-on: ubuntu-latest
env:
  MAKEFLAGS: "-j2"  # Parallel compilation
  R_COMPILE_PKGS: "1"  # Byte-compile packages
```

## Deployment Strategies

### Environment Configuration

```yaml
# Production deployment
deploy-production:
  environment:
    name: production
    url: https://league-simulator.example.com
  concurrency:
    group: production
    cancel-in-progress: false
```

### Health Checks

Comprehensive health validation:

```r
# docker/healthcheck-league.R
health_check <- function() {
  checks <- list(
    api_connection = test_api_connection(),
    data_files = check_data_files(),
    write_permissions = test_write_permissions(),
    memory_available = check_memory()
  )
  
  if (!all(unlist(checks))) {
    stop("Health check failed")
  }
  
  return(TRUE)
}
```

### Rollback Strategy

Automatic rollback on deployment failure:

```yaml
- name: Deploy with rollback
  run: |
    # Save current version
    CURRENT_VERSION=$(docker ps --format "table {{.Image}}" | grep league-simulator | head -1)
    
    # Deploy new version
    docker-compose up -d --no-deps league-simulator
    
    # Health check
    if ! docker exec league-simulator Rscript /app/docker/healthcheck-league.R; then
      echo "Deployment failed, rolling back..."
      docker-compose down
      docker run -d $CURRENT_VERSION
      exit 1
    fi
```

## Monitoring Integration

### Performance Metrics

Track key performance indicators:

```yaml
# .github/workflows/ci-dashboard.yml
- name: Collect metrics
  run: |
    echo "BUILD_TIME=${{ steps.timer.outputs.time }}" >> metrics.txt
    echo "TEST_PASSED=${{ steps.test.outputs.passed }}" >> metrics.txt
    echo "TEST_TOTAL=${{ steps.test.outputs.total }}" >> metrics.txt
    echo "CACHE_HIT=${{ steps.cache.outputs.cache-hit }}" >> metrics.txt
```

### Automated Reporting

Generate performance dashboards:

```r
# .github/scripts/test-summary.R
generate_dashboard <- function() {
  metrics <- read_metrics()
  
  dashboard <- create_dashboard(
    title = "CI/CD Performance",
    metrics = list(
      success_rate = calculate_success_rate(metrics),
      avg_build_time = mean(metrics$build_time),
      test_coverage = calculate_coverage(metrics),
      flaky_tests = count_flaky_tests(metrics)
    )
  )
  
  save_dashboard(dashboard, "ci-performance.html")
}
```

## Security Considerations

### Secret Management

```yaml
# Never commit secrets
env:
  RAPIDAPI_KEY: ${{ secrets.RAPIDAPI_KEY }}
  SHINYAPPS_TOKEN: ${{ secrets.SHINYAPPS_TOKEN }}

# Use environment-specific secrets
deploy:
  environment: production
  env:
    API_KEY: ${{ secrets.PROD_API_KEY }}
```

### Dependency Scanning

Regular security updates:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

## Troubleshooting

### Common Issues

1. **Test Timeouts**
   - Increase timeout in workflow
   - Check for hanging tests
   - Review resource constraints

2. **Cache Misses**
   - Verify cache key strategy
   - Check for unnecessary cache busting
   - Monitor cache size limits

3. **Flaky Tests**
   - Check quarantine list
   - Review test isolation
   - Verify external dependencies

### Debug Mode

Enable verbose logging:

```yaml
- name: Run tests with debugging
  env:
    CI_DEBUG: "true"
    R_VERBOSE: "true"
  run: |
    Rscript tests/testthat.R --reporter=verbose
```

## Best Practices

### 1. Fail Fast
- Use `fail-fast: false` for test matrix
- But fail immediately on critical errors
- Provide clear error messages

### 2. Progressive Enhancement
- Start with basic CI
- Add features incrementally
- Monitor impact of changes

### 3. Documentation
- Document CI configuration
- Explain custom scripts
- Maintain troubleshooting guide

### 4. Regular Maintenance
- Review and update timeouts
- Clean up old workflow runs
- Update dependencies regularly

## Migration Guide

### From Basic CI to Enhanced Pipeline

1. **Phase 1: Stabilization**
   - Fix failing tests
   - Remove error masking
   - Establish baseline metrics

2. **Phase 2: Optimization**
   - Implement caching
   - Add parallel execution
   - Optimize Docker builds

3. **Phase 3: Enhancement**
   - Add monitoring
   - Implement retry logic
   - Create dashboards

4. **Phase 4: Automation**
   - Automate common tasks
   - Add self-healing capabilities
   - Implement predictive features

## Workflow Examples

### Basic Test Workflow
```yaml
name: R Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v3
      - uses: r-lib/actions/setup-r@v2
      - name: Install dependencies
        run: |
          Rscript -e "install.packages('testthat')"
      - name: Run tests
        run: |
          Rscript tests/testthat.R
```

### Advanced Parallel Workflow
```yaml
name: Parallel Tests
on: [push, pull_request]
jobs:
  test:
    strategy:
      matrix:
        shard: [1, 2, 3, 4]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run shard ${{ matrix.shard }}
        run: |
          Rscript .github/scripts/shard-tests.R \
            --shard ${{ matrix.shard }} \
            --total 4
```

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [R Package Testing](https://r-pkgs.org/tests.html)
- [CI/CD Performance Report](../ci-performance-report.md)
- [CI Monitoring Guide](../operations/ci-monitoring.md)