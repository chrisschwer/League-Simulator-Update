#!/bin/bash
set -e

# Local deployment script for League Simulator
# This script deploys to a local Kubernetes cluster (Docker Desktop, minikube, etc.)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        echo "Installation guide: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        echo "Installation guide: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster."
        echo "Make sure your cluster is running (Docker Desktop, minikube, etc.)"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to build Docker images locally
build_images() {
    print_status "Building Docker images locally..."
    
    cd "$PROJECT_ROOT"
    
    # Build league service image
    print_status "Building league service image..."
    docker build -f Dockerfile.league -t league-simulator:league .
    
    # Build shiny service image
    print_status "Building shiny service image..."
    docker build -f Dockerfile.shiny -t league-simulator:shiny .
    
    print_success "Docker images built successfully"
}

# Function to create namespace and secrets
setup_cluster() {
    print_status "Setting up Kubernetes cluster..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace league-simulator --dry-run=client -o yaml | kubectl apply -f -
    
    # Check if secrets need to be created
    if ! kubectl -n league-simulator get secret league-simulator-secrets &> /dev/null; then
        print_warning "API secrets not found. Creating placeholder secrets."
        print_warning "Please update these secrets with your actual API keys:"
        
        kubectl -n league-simulator create secret generic league-simulator-secrets \
            --from-literal=RAPIDAPI_KEY="your-rapidapi-key-here" \
            --from-literal=SHINYAPPS_IO_SECRET="your-shinyapps-secret-here"
        
        echo ""
        print_warning "To update secrets later, use:"
        echo "kubectl -n league-simulator patch secret league-simulator-secrets -p '{\"stringData\":{\"RAPIDAPI_KEY\":\"your-key\"}}'"
        echo ""
    fi
    
    print_success "Cluster setup complete"
}

# Function to deploy applications
deploy_apps() {
    print_status "Deploying League Simulator applications..."
    
    # Apply Kubernetes manifests
    kubectl apply -f "$PROJECT_ROOT/k8s/"
    
    print_status "Waiting for deployments to be ready..."
    
    # Wait for deployments with timeout
    kubectl -n league-simulator wait --for=condition=available deployment --all --timeout=300s
    
    print_success "All deployments are ready"
}

# Function to show deployment status
show_status() {
    print_status "Deployment Status:"
    echo ""
    
    echo "🏆 Pods:"
    kubectl -n league-simulator get pods -o wide
    echo ""
    
    echo "📊 Deployments:"
    kubectl -n league-simulator get deployments
    echo ""
    
    echo "💾 Storage:"
    kubectl -n league-simulator get pvc
    echo ""
    
    echo "🔧 Services:"
    kubectl -n league-simulator get services
    echo ""
}

# Function to show next steps
show_next_steps() {
    print_success "🎉 League Simulator deployed successfully!"
    echo ""
    echo "📋 Next Steps:"
    echo "1. Check status: kubectl -n league-simulator get pods"
    echo "2. View logs: kubectl -n league-simulator logs -l app=league-updater"
    echo "3. Update API keys: kubectl -n league-simulator patch secret league-simulator-secrets -p '{\"stringData\":{\"RAPIDAPI_KEY\":\"your-key\"}}'"
    echo "4. Scale services: kubectl -n league-simulator scale deployment league-updater-bl --replicas=2"
    echo ""
    echo "🔧 Useful Commands:"
    echo "- Status check: $SCRIPT_DIR/status.sh"
    echo "- Update deployment: kubectl -n league-simulator rollout restart deployment/league-updater-bl"
    echo "- Remove everything: kubectl delete namespace league-simulator"
    echo ""
}

# Main deployment function
main() {
    echo "🚀 League Simulator Local Deployment"
    echo "===================================="
    echo ""
    
    # Parse command line arguments
    BUILD_IMAGES=true
    SKIP_BUILD=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --skip-build    Skip Docker image building (use existing images)"
                echo "  --help          Show this help message"
                echo ""
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    
    if [ "$SKIP_BUILD" = false ]; then
        build_images
    else
        print_status "Skipping image build (using existing images)"
    fi
    
    setup_cluster
    deploy_apps
    show_status
    show_next_steps
}

# Run main function
main "$@"