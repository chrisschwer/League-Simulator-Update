#!/bin/bash
# Test multi-stage Docker build functionality

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Running Docker multi-stage build tests..."

# Test 1: Multi-stage build success
test_multistage_build() {
  echo -n "Testing multi-stage Docker build... "
  
  # Build the optimized image
  if docker build -f Dockerfile.league.optimized -t test-league-optimized . > /tmp/docker-build.log 2>&1; then
    # Verify both stages completed by checking build output
    if grep -q "FROM rocker/r-ver:4.3.1 AS builder" /tmp/docker-build.log; then
      echo -e "${GREEN}PASS${NC}"
      return 0
    else
      echo -e "${RED}FAIL${NC}: Builder stage not found in build log"
      return 1
    fi
  else
    echo -e "${RED}FAIL${NC}: Multi-stage build failed"
    cat /tmp/docker-build.log
    return 1
  fi
}

# Test 2: Verify package copying between stages
test_package_copying() {
  echo -n "Testing package copying between stages... "
  
  # Check if R packages are available in runtime
  if docker run --rm test-league-optimized Rscript -e "library(httr); cat('SUCCESS')" 2>/dev/null | grep -q "SUCCESS"; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${RED}FAIL${NC}: Packages not available in runtime stage"
    return 1
  fi
}

# Test 3: Verify non-root user
test_nonroot_user() {
  echo -n "Testing non-root user configuration... "
  
  # Check user ID
  user_id=$(docker run --rm test-league-optimized id -u)
  if [ "$user_id" = "1000" ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${RED}FAIL${NC}: Expected user ID 1000, got $user_id"
    return 1
  fi
}

# Run all tests
failed=0
test_multistage_build || ((failed++))
test_package_copying || ((failed++))
test_nonroot_user || ((failed++))

# Cleanup
docker rmi test-league-optimized 2>/dev/null || true
rm -f /tmp/docker-build.log

# Summary
echo ""
if [ $failed -eq 0 ]; then
  echo -e "${GREEN}All multi-stage build tests passed!${NC}"
  exit 0
else
  echo -e "${RED}$failed tests failed${NC}"
  exit 1
fi