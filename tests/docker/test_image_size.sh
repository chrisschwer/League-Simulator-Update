#!/bin/bash
# Test Docker image size reduction

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "Running Docker image size comparison tests..."

# Function to convert size to bytes
size_to_bytes() {
  local size=$1
  local number=$(echo $size | sed 's/[^0-9.]//g')
  local unit=$(echo $size | sed 's/[0-9.]//g')
  
  case $unit in
    GB) echo $(echo "$number * 1073741824" | bc | cut -d. -f1) ;;
    MB) echo $(echo "$number * 1048576" | bc | cut -d. -f1) ;;
    KB) echo $(echo "$number * 1024" | bc | cut -d. -f1) ;;
    *) echo $number ;;
  esac
}

# Build original image if Dockerfile.league exists
if [ -f "Dockerfile.league" ]; then
  echo "Building original image..."
  docker build -f Dockerfile.league -t league-original . > /tmp/build-original.log 2>&1 || {
    echo -e "${RED}Failed to build original image${NC}"
    exit 1
  }
else
  echo -e "${YELLOW}Warning: Dockerfile.league not found, using base rocker/tidyverse for comparison${NC}"
  docker pull rocker/tidyverse:4.3.1
  docker tag rocker/tidyverse:4.3.1 league-original
fi

# Build optimized image
echo "Building optimized image..."
if [ -f "Dockerfile.league.optimized" ]; then
  docker build -f Dockerfile.league.optimized -t league-optimized . > /tmp/build-optimized.log 2>&1 || {
    echo -e "${RED}Failed to build optimized image${NC}"
    exit 1
  }
else
  echo -e "${RED}Dockerfile.league.optimized not found${NC}"
  exit 1
fi

# Get image sizes
size_original=$(docker images league-original --format "{{.Size}}")
size_optimized=$(docker images league-optimized --format "{{.Size}}")

# Convert to bytes for accurate comparison
bytes_original=$(size_to_bytes "$size_original")
bytes_optimized=$(size_to_bytes "$size_optimized")

# Calculate reduction
if [ $bytes_original -gt 0 ]; then
  reduction=$(( (bytes_original - bytes_optimized) * 100 / bytes_original ))
else
  echo -e "${RED}Failed to get original image size${NC}"
  exit 1
fi

# Display results
echo ""
echo "Image Size Comparison:"
echo "----------------------"
echo "Original image:   $size_original"
echo "Optimized image:  $size_optimized"
echo "Size reduction:   $reduction%"
echo ""

# Check if optimized image is under 500MB
mb_optimized=$(( bytes_optimized / 1048576 ))
if [ $mb_optimized -lt 500 ]; then
  echo -e "${GREEN}✓ Optimized image is under 500MB target${NC}"
else
  echo -e "${YELLOW}⚠ Optimized image exceeds 500MB target${NC}"
fi

# Check reduction percentage
if [ $reduction -ge 60 ]; then
  echo -e "${GREEN}✓ Size reduced by $reduction% (target: 60%)${NC}"
  exit_code=0
else
  echo -e "${RED}✗ Insufficient size reduction: $reduction% (target: 60%)${NC}"
  exit_code=1
fi

# Cleanup
docker rmi league-original league-optimized 2>/dev/null || true
rm -f /tmp/build-*.log

exit $exit_code