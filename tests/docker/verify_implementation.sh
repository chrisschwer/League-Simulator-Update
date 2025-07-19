#!/bin/bash
# Verify Docker optimization implementation

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Docker Optimization Implementation Verification${NC}"
echo "=============================================="
echo ""

# Track verification results
passed=0
total=0

# Function to check file exists
check_file() {
    local file=$1
    local description=$2
    ((total++))
    
    echo -n "Checking $description... "
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((passed++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} - File not found: $file"
        return 1
    fi
}

# Function to check file contains pattern
check_contains() {
    local file=$1
    local pattern=$2
    local description=$3
    ((total++))
    
    echo -n "Checking $description... "
    if [ -f "$file" ] && grep -q "$pattern" "$file"; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((passed++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} - Pattern not found in $file"
        return 1
    fi
}

# 1. Check .dockerignore
echo -e "${BLUE}1. Docker Build Context Optimization${NC}"
check_file ".dockerignore" ".dockerignore exists"
check_contains ".dockerignore" "^.git$" ".dockerignore excludes .git"
check_contains ".dockerignore" "^tests/" ".dockerignore excludes tests"
echo ""

# 2. Check Dockerfiles
echo -e "${BLUE}2. Dockerfile Optimizations${NC}"
check_file "Dockerfile.optimized" "Optimized Dockerfile exists"
check_contains "Dockerfile.optimized" "FROM rocker/r-ver:4.3.1 AS builder" "Multi-stage build"
check_contains "Dockerfile.optimized" "USER appuser" "Non-root user"
check_contains "Dockerfile.optimized" "HEALTHCHECK" "Health check implemented"

check_contains "Dockerfile.league" "FROM rocker/r-ver:4.3.1 AS builder" "League: Multi-stage build"
check_contains "Dockerfile.league" "USER appuser" "League: Non-root user"
check_contains "Dockerfile.league" "HEALTHCHECK" "League: Health check"

check_contains "Dockerfile.shiny" "FROM rocker/r-ver:4.3.1 AS builder" "Shiny: Multi-stage build"
check_contains "Dockerfile.shiny" "USER appuser" "Shiny: Non-root user"
check_contains "Dockerfile.shiny" "HEALTHCHECK" "Shiny: Health check"
echo ""

# 3. Check security features
echo -e "${BLUE}3. Security Features${NC}"
check_contains "Dockerfile.optimized" "apt-get upgrade" "System updates in monolithic"
check_contains "Dockerfile.league" "apt-get upgrade" "System updates in league"
check_contains "Dockerfile.shiny" "apt-get upgrade" "System updates in shiny"
check_contains "Dockerfile.optimized" "useradd.*1000" "UID 1000 configured"
echo ""

# 4. Check performance optimizations
echo -e "${BLUE}4. Performance Optimizations${NC}"
check_contains "Dockerfile.optimized" "Ncpus=4" "Parallel package installation"
check_contains "Dockerfile.optimized" "COPY --from=builder" "Multi-stage copy"
check_contains "packagelist.txt" "^dplyr$" "Updated package list"
echo ""

# 5. Check supporting files
echo -e "${BLUE}5. Supporting Files${NC}"
check_file "scripts/docker_build_all.sh" "Build script exists"
check_file "docs/docker_optimization/documentation_updates.md" "Documentation updates"
check_file "tests/docker/test_multistage_build.sh" "Test script exists"
echo ""

# 6. Check documentation strategy
echo -e "${BLUE}6. Documentation Strategy${NC}"
if [ -f "docs/docker_optimization/documentation_updates.md" ]; then
    echo -e "${GREEN}✓ PASS${NC} - Documentation in separate file (no README conflicts)"
    ((passed++))
    ((total++))
else
    echo -e "${RED}✗ FAIL${NC} - Documentation strategy not implemented"
    ((total++))
fi
echo ""

# Summary
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo "Total checks: $total"
echo "Passed: $passed"
echo "Failed: $((total - passed))"
echo ""

if [ $passed -eq $total ]; then
    echo -e "${GREEN}All implementation checks passed! ✓${NC}"
    echo ""
    echo "The Docker optimization implementation is complete and ready for:"
    echo "1. Running 'Rscript init_renv.R' to create renv.lock"
    echo "2. Building images with 'bash scripts/docker_build_all.sh'"
    echo "3. Running full test suite"
    exit 0
else
    echo -e "${RED}Some checks failed ✗${NC}"
    echo "Please review the failed items above."
    exit 1
fi