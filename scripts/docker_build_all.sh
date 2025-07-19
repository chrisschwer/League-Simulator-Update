#!/bin/bash
# Build all optimized Docker images for League Simulator

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
REGISTRY=${DOCKER_REGISTRY:-""}  # Set DOCKER_REGISTRY env var to push to registry
TAG=${1:-"latest"}

echo -e "${BLUE}Building League Simulator Docker images...${NC}"
echo "Tag: $TAG"
echo ""

# Function to build and optionally push image
build_image() {
    local dockerfile=$1
    local image_name=$2
    local build_name="${REGISTRY:+$REGISTRY/}league-simulator:$image_name-$TAG"

    echo -e "${BLUE}Building $image_name from $dockerfile...${NC}"

    if docker build -f "$dockerfile" -t "$build_name" .; then
        echo -e "${GREEN}✓ Successfully built $build_name${NC}"

        # Tag as latest if building latest
        if [ "$TAG" = "latest" ]; then
            docker tag "$build_name" "${REGISTRY:+$REGISTRY/}league-simulator:$image_name"
        fi

        # Push if registry is set
        if [ -n "$REGISTRY" ]; then
            echo "Pushing to $REGISTRY..."
            docker push "$build_name"
            [ "$TAG" = "latest" ] && docker push "${REGISTRY:+$REGISTRY/}league-simulator:$image_name"
        fi

        return 0
    else
        echo -e "${RED}✗ Failed to build $image_name${NC}"
        return 1
    fi
}

# Check if we're in the right directory
if [ ! -f "Dockerfile.optimized" ]; then
    echo -e "${RED}Error: This script must be run from the project root directory${NC}"
    exit 1
fi

# Track build results
failed=0

# Build monolithic image
build_image "Dockerfile.optimized" "monolithic" || ((failed++))
echo ""

# Build league updater
build_image "Dockerfile.league" "league" || ((failed++))
echo ""

# Build shiny updater
build_image "Dockerfile.shiny" "shiny" || ((failed++))
echo ""

# Summary
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Build Summary${NC}"
echo -e "${BLUE}======================================${NC}"

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All images built successfully!${NC}"
    echo ""
    echo "Images created:"
    docker images "league-simulator" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "(monolithic|league|shiny)"
else
    echo -e "${RED}$failed image(s) failed to build${NC}"
    exit 1
fi

# Optional: Run size comparison if old images exist
echo ""
echo -e "${BLUE}Image Size Comparison:${NC}"
for img in monolithic league shiny; do
    if docker images | grep -q "league-simulator.*$img.*latest"; then
        size=$(docker images "league-simulator:$img-$TAG" --format "{{.Size}}" 2>/dev/null || echo "N/A")
        echo "- $img: $size"
    fi
done

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Test images: bash tests/docker/run_all_tests.sh"
echo "2. Run locally: docker run -e RAPIDAPI_KEY=xxx league-simulator:league-$TAG"
echo "3. Deploy to Kubernetes: kubectl apply -f k8s/"