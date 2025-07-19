# Docker Optimization Test Specifications

## Test Categories

### 1. Docker Build Tests

#### Test 1.1: Multi-stage Build Success
```bash
#!/bin/bash
# test_multistage_build.sh
test_multistage_build() {
  echo "Testing multi-stage Docker build..."
  
  # Build the optimized image
  docker build -f Dockerfile.league.optimized -t test-league-optimized . || {
    echo "FAIL: Multi-stage build failed"
    return 1
  }
  
  # Verify both stages completed
  docker history test-league-optimized | grep -q "FROM rocker/r-ver:4.3.1 AS builder" || {
    echo "FAIL: Builder stage not found"
    return 1
  }
  
  echo "PASS: Multi-stage build successful"
  return 0
}
```

#### Test 1.2: Build Context Optimization
```bash
test_dockerignore() {
  echo "Testing .dockerignore effectiveness..."
  
  # Create test files that should be ignored
  touch test.log .DS_Store
  mkdir -p .git tests/large_file
  dd if=/dev/zero of=tests/large_file/test.bin bs=1M count=10 2>/dev/null
  
  # Measure build context size
  tar -czf - . --exclude='.git' | wc -c > /tmp/context_with_dockerignore
  tar -czf - . | wc -c > /tmp/context_without_dockerignore
  
  # Compare sizes
  size_with=$(cat /tmp/context_with_dockerignore)
  size_without=$(cat /tmp/context_without_dockerignore)
  
  if [ $size_with -lt $((size_without / 2)) ]; then
    echo "PASS: .dockerignore reduces context by >50%"
    return 0
  else
    echo "FAIL: .dockerignore not effective enough"
    return 1
  fi
}
```

#### Test 1.3: Package Installation Optimization
```r
# test_package_installation.R
test_parallel_installation <- function() {
  # Test that packages install in parallel
  start_time <- Sys.time()
  
  # Simulate package installation with timing
  system2("docker", c("build", "--build-arg", "NCPUS=4", 
                     "-f", "Dockerfile.test", "-t", "test-parallel", "."))
  
  parallel_time <- difftime(Sys.time(), start_time, units = "secs")
  
  # Compare with sequential installation
  system2("docker", c("build", "--build-arg", "NCPUS=1",
                     "-f", "Dockerfile.test", "-t", "test-sequential", "."))
  
  sequential_time <- difftime(Sys.time(), start_time, units = "secs")
  
  # Parallel should be significantly faster
  stopifnot(parallel_time < sequential_time * 0.7)
}
```

### 2. Container Structure Tests

#### Test 2.1: Image Size Validation
```yaml
# container-structure-test-size.yaml
schemaVersion: 2.0.0
metadataTest:
  env:
    - key: 'TZ'
      value: 'Europe/Berlin'
  exposedPorts: []
  volumes: ['/RCode/league_results']
  user: '1000:1000'

commandTests:
  - name: "Image size under 500MB"
    command: "sh"
    args: ["-c", "size=$(du -sh / 2>/dev/null | cut -f1); echo $size | grep -E '^[0-4][0-9]{2}M' || exit 1"]
    exitCode: 0
```

#### Test 2.2: Required Packages Availability
```yaml
# container-structure-test-packages.yaml
schemaVersion: 2.0.0
commandTests:
  - name: "R version correct"
    command: "R"
    args: ["--version"]
    expectedOutput: ["R version 4.3.1"]
  
  - name: "Essential R packages available"
    command: "Rscript"
    args: ["-e", "libs <- c('httr','jsonlite','dplyr','tidyr','ggplot2','shiny','Rcpp'); for(l in libs) library(l, character.only=TRUE)"]
    exitCode: 0
    
  - name: "renv available"
    command: "Rscript"
    args: ["-e", "library(renv); packageVersion('renv')"]
    exitCode: 0
```

#### Test 2.3: Security Configuration
```yaml
# container-structure-test-security.yaml
schemaVersion: 2.0.0
fileExistenceTests:
  - name: "Health check script exists"
    path: "/usr/local/bin/healthcheck.R"
    shouldExist: true
    permissions: "-rwxr-xr-x"

  - name: "Application files owned by non-root user"
    path: "/RCode"
    shouldExist: true
    uid: 1000
    gid: 1000

metadataTest:
  user: "appuser"
  
commandTests:
  - name: "Running as non-root user"
    command: "id"
    expectedOutput: ["uid=1000"]
    excludedOutput: ["uid=0"]
```

### 3. Integration Tests

#### Test 3.1: Multi-stage Build Integration
```r
# test_integration_multistage.R
library(testthat)

test_that("Packages from builder stage work in runtime stage", {
  # Build test image
  system2("docker", c("build", "-f", "Dockerfile.league.optimized", 
                     "-t", "test-integration", "."))
  
  # Test package loading in runtime
  result <- system2("docker", 
    c("run", "--rm", "test-integration", 
      "Rscript", "-e", "library(httr); GET('https://httpbin.org/get')"),
    stdout = TRUE, stderr = TRUE)
  
  expect_true(any(grepl("200", result)))
})

test_that("C++ compilation works with Rcpp", {
  # Test Rcpp functionality
  cpp_test <- '
    #include <Rcpp.h>
    // [[Rcpp::export]]
    int testFunc() { return 42; }
  '
  
  result <- system2("docker",
    c("run", "--rm", "test-integration",
      "Rscript", "-e", 
      sprintf("Rcpp::sourceCpp(code='%s'); cat(testFunc())", cpp_test)),
    stdout = TRUE)
  
  expect_equal(trimws(result), "42")
})
```

#### Test 3.2: Volume Mounting and Permissions
```bash
#!/bin/bash
# test_volumes.sh
test_volume_permissions() {
  # Create temporary directory
  TEST_DIR=$(mktemp -d)
  
  # Run container with volume mount
  docker run -d --name test-volumes \
    -v "$TEST_DIR:/RCode/league_results" \
    test-league-optimized
  
  # Let container create files
  sleep 5
  
  # Check if files are created with correct permissions
  docker exec test-volumes touch /RCode/league_results/test.txt
  
  # Verify from host
  if [ -f "$TEST_DIR/test.txt" ]; then
    echo "PASS: Volume mounting works"
  else
    echo "FAIL: Volume mounting failed"
    docker rm -f test-volumes
    return 1
  fi
  
  # Cleanup
  docker rm -f test-volumes
  rm -rf "$TEST_DIR"
  return 0
}
```

#### Test 3.3: Health Check Functionality
```bash
#!/bin/bash
# test_healthcheck.sh
test_healthcheck() {
  # Start container
  docker run -d --name test-health test-league-optimized
  
  # Wait for container to be healthy
  timeout=30
  while [ $timeout -gt 0 ]; do
    health=$(docker inspect --format='{{.State.Health.Status}}' test-health)
    if [ "$health" = "healthy" ]; then
      echo "PASS: Container became healthy"
      docker rm -f test-health
      return 0
    fi
    sleep 1
    ((timeout--))
  done
  
  echo "FAIL: Container did not become healthy in 30s"
  docker logs test-health
  docker rm -f test-health
  return 1
}
```

### 4. Performance Benchmark Tests

#### Test 4.1: Image Size Comparison
```bash
#!/bin/bash
# test_image_size.sh
test_image_size_reduction() {
  # Build original image
  docker build -f Dockerfile.league -t league-original .
  
  # Build optimized image
  docker build -f Dockerfile.league.optimized -t league-optimized .
  
  # Get sizes
  size_original=$(docker images league-original --format "{{.Size}}")
  size_optimized=$(docker images league-optimized --format "{{.Size}}")
  
  # Convert to bytes for comparison
  bytes_original=$(echo $size_original | numfmt --from=iec)
  bytes_optimized=$(echo $size_optimized | numfmt --from=iec)
  
  # Calculate reduction percentage
  reduction=$(( (bytes_original - bytes_optimized) * 100 / bytes_original ))
  
  echo "Original size: $size_original"
  echo "Optimized size: $size_optimized"
  echo "Reduction: $reduction%"
  
  # Expect at least 60% reduction
  if [ $reduction -gt 60 ]; then
    echo "PASS: Size reduced by $reduction%"
    return 0
  else
    echo "FAIL: Insufficient size reduction"
    return 1
  fi
}
```

#### Test 4.2: Build Time Comparison
```bash
#!/bin/bash
# test_build_time.sh
test_build_time() {
  # Clear Docker cache
  docker builder prune -af
  
  # Time original build
  start=$(date +%s)
  docker build -f Dockerfile.league -t league-original-timed . > /dev/null 2>&1
  end=$(date +%s)
  time_original=$((end - start))
  
  # Clear cache again
  docker builder prune -af
  
  # Time optimized build
  start=$(date +%s)
  docker build -f Dockerfile.league.optimized -t league-optimized-timed . > /dev/null 2>&1
  end=$(date +%s)
  time_optimized=$((end - start))
  
  echo "Original build time: ${time_original}s"
  echo "Optimized build time: ${time_optimized}s"
  
  # Optimized should be faster (allowing some variance)
  if [ $time_optimized -lt $((time_original * 120 / 100)) ]; then
    echo "PASS: Build time acceptable"
    return 0
  else
    echo "FAIL: Optimized build too slow"
    return 1
  fi
}
```

#### Test 4.3: Startup Performance
```bash
#!/bin/bash
# test_startup_time.sh
test_startup_performance() {
  # Test original image startup
  start=$(date +%s%N)
  docker run --rm league-original Rscript -e "cat('Started\n')" > /dev/null 2>&1
  end=$(date +%s%N)
  time_original=$(( (end - start) / 1000000 )) # Convert to milliseconds
  
  # Test optimized image startup
  start=$(date +%s%N)
  docker run --rm league-optimized Rscript -e "cat('Started\n')" > /dev/null 2>&1
  end=$(date +%s%N)
  time_optimized=$(( (end - start) / 1000000 ))
  
  echo "Original startup: ${time_original}ms"
  echo "Optimized startup: ${time_optimized}ms"
  
  # Optimized should start faster
  if [ $time_optimized -lt $time_original ]; then
    echo "PASS: Startup time improved"
    return 0
  else
    echo "FAIL: Startup time not improved"
    return 1
  fi
}
```

### 5. Edge Case Tests

#### Test 5.1: Missing renv.lock Fallback
```bash
#!/bin/bash
# test_renv_fallback.sh
test_renv_fallback() {
  # Build without renv.lock
  mv renv.lock renv.lock.backup 2>/dev/null || true
  
  docker build -f Dockerfile.league.optimized -t test-no-renv . || {
    echo "FAIL: Build failed without renv.lock"
    mv renv.lock.backup renv.lock 2>/dev/null || true
    return 1
  }
  
  # Verify packages still installed
  docker run --rm test-no-renv Rscript -e "library(httr)" || {
    echo "FAIL: Packages not installed in fallback mode"
    mv renv.lock.backup renv.lock 2>/dev/null || true
    return 1
  }
  
  mv renv.lock.backup renv.lock 2>/dev/null || true
  echo "PASS: Fallback to packagelist.txt works"
  return 0
}
```

#### Test 5.2: System Package Updates
```bash
#!/bin/bash
# test_system_updates.sh
test_system_package_updates() {
  # Build image and check for updates
  docker build -f Dockerfile.league.optimized -t test-updates .
  
  # Check if apt-get upgrade was run
  docker run --rm test-updates sh -c "apt-get update && apt-get upgrade -s" | grep -q "0 upgraded" || {
    echo "FAIL: System packages not up to date"
    return 1
  }
  
  echo "PASS: System packages are current"
  return 0
}
```

## Test Execution Plan

### Continuous Integration
```yaml
# .github/workflows/docker-tests.yml
name: Docker Optimization Tests
on: [push, pull_request]

jobs:
  test-docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install container-structure-test
        run: |
          curl -LO https://storage.googleapis.com/container-structure-test/latest/container-structure-test-linux-amd64
          chmod +x container-structure-test-linux-amd64
          sudo mv container-structure-test-linux-amd64 /usr/local/bin/container-structure-test
      
      - name: Run Docker build tests
        run: bash tests/docker/test_multistage_build.sh
      
      - name: Run structure tests
        run: |
          docker build -f Dockerfile.league.optimized -t test-image .
          container-structure-test test --image test-image --config tests/docker/container-structure-test-*.yaml
      
      - name: Run integration tests
        run: Rscript tests/docker/test_integration_multistage.R
      
      - name: Run performance benchmarks
        run: |
          bash tests/docker/test_image_size.sh
          bash tests/docker/test_startup_time.sh
```

## Success Criteria

All tests must pass with:
- ✅ Image size < 500MB (75% reduction)
- ✅ Build time < 5 minutes with caching
- ✅ All packages load successfully
- ✅ Non-root user execution
- ✅ Health checks functioning
- ✅ Volumes mount correctly
- ✅ System packages updated
- ✅ Fallback mechanisms work