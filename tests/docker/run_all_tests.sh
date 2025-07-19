#!/bin/bash
# Run all Docker optimization tests

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Docker Optimization Test Suite${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Track test results
total_tests=0
passed_tests=0

# Function to run a test and track results
run_test() {
  local test_name=$1
  local test_command=$2
  
  echo -e "${BLUE}Running: $test_name${NC}"
  ((total_tests++))
  
  if eval "$test_command"; then
    ((passed_tests++))
    echo -e "${GREEN}✓ $test_name passed${NC}"
  else
    echo -e "${RED}✗ $test_name failed${NC}"
  fi
  echo ""
}

# Create .dockerignore if it doesn't exist
if [ ! -f ".dockerignore" ]; then
  echo "Creating .dockerignore for testing..."
  cat > .dockerignore << EOF
.git
.github
*.md
*.log
.DS_Store
tests/
docs/
k8s/
*.tar.gz
*.zip
.Rhistory
.RData
EOF
fi

# 1. Multi-stage build tests
if [ -f "tests/docker/test_multistage_build.sh" ]; then
  run_test "Multi-stage build tests" "bash tests/docker/test_multistage_build.sh"
fi

# 2. Container structure tests
if command -v container-structure-test &> /dev/null; then
  # Build image for structure tests
  if [ -f "Dockerfile.league.optimized" ]; then
    echo "Building image for structure tests..."
    docker build -f Dockerfile.league.optimized -t test-structure . > /dev/null 2>&1
    
    if [ -f "tests/docker/container-structure-test-packages.yaml" ]; then
      run_test "Package availability tests" \
        "container-structure-test test --image test-structure --config tests/docker/container-structure-test-packages.yaml"
    fi
    
    if [ -f "tests/docker/container-structure-test-security.yaml" ]; then
      run_test "Security configuration tests" \
        "container-structure-test test --image test-structure --config tests/docker/container-structure-test-security.yaml"
    fi
    
    docker rmi test-structure 2>/dev/null || true
  fi
else
  echo -e "${YELLOW}Warning: container-structure-test not installed, skipping structure tests${NC}"
  echo "Install from: https://github.com/GoogleContainerTools/container-structure-test"
  echo ""
fi

# 3. Image size tests
if [ -f "tests/docker/test_image_size.sh" ]; then
  run_test "Image size comparison" "bash tests/docker/test_image_size.sh"
fi

# 4. Health check test
if [ -f "Dockerfile.league.optimized" ]; then
  run_test "Health check functionality" "docker build -f Dockerfile.league.optimized -t test-health . > /dev/null 2>&1 && \
    docker run -d --name test-health-container test-health > /dev/null 2>&1 && \
    sleep 5 && \
    docker inspect --format='{{.State.Health.Status}}' test-health-container | grep -q healthy && \
    docker rm -f test-health-container > /dev/null 2>&1 && \
    docker rmi test-health > /dev/null 2>&1"
fi

# Summary
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo "Total tests: $total_tests"
echo "Passed: $passed_tests"
echo "Failed: $((total_tests - passed_tests))"
echo ""

if [ $passed_tests -eq $total_tests ]; then
  echo -e "${GREEN}All tests passed! ✓${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed ✗${NC}"
  exit 1
fi