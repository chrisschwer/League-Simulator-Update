#!/bin/bash
# Deploy Pod Lifecycle Management System
# Implements CronJob-based pod scaling for resource optimization

set -e

NAMESPACE="league-simulator"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

deploy_component() {
    local component="$1"
    local path="$2"
    
    log "Deploying $component..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: Would deploy $component from $path"
        kubectl apply -f "$path" --dry-run=client --validate=true
    else
        kubectl apply -f "$path"
        success "Deployed $component"
    fi
}

validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is required but not installed"
        exit 1
    fi
    
    # Check if we can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        warning "Namespace $NAMESPACE does not exist, creating..."
        if [[ "$DRY_RUN" != "true" ]]; then
            kubectl create namespace "$NAMESPACE"
        fi
    fi
    
    success "Prerequisites validated"
}

deploy_rbac() {
    log "Deploying RBAC configuration..."
    deploy_component "ServiceAccount" "k8s/rbac/serviceaccount.yaml"
    deploy_component "Role" "k8s/rbac/role.yaml"
    deploy_component "RoleBinding" "k8s/rbac/rolebinding.yaml"
    success "RBAC configuration deployed"
}

deploy_cronjobs() {
    log "Deploying CronJobs (suspended for safety)..."
    
    local cronjob_count=0
    for cronjob_file in k8s/cronjobs/**/*.yaml; do
        if [[ -f "$cronjob_file" ]]; then
            deploy_component "CronJob $(basename "$cronjob_file" .yaml)" "$cronjob_file"
            ((cronjob_count++))
        fi
    done
    
    success "Deployed $cronjob_count CronJobs (all suspended)"
    warning "CronJobs are suspended for safety. Use ./scripts/activate_lifecycle.sh to enable."
}

deploy_monitoring() {
    log "Deploying monitoring configuration..."
    
    if [[ -f "k8s/monitoring/cronjob-monitor.yaml" ]]; then
        deploy_component "ServiceMonitor" "k8s/monitoring/cronjob-monitor.yaml"
    fi
    
    if [[ -f "k8s/monitoring/alerts.yaml" ]]; then
        deploy_component "PrometheusRule" "k8s/monitoring/alerts.yaml"
    fi
    
    success "Monitoring configuration deployed"
}

verify_deployment() {
    log "Verifying deployment..."
    
    # Check RBAC
    if kubectl get serviceaccount pod-lifecycle-manager -n "$NAMESPACE" &> /dev/null; then
        success "ServiceAccount created"
    else
        error "ServiceAccount not found"
        return 1
    fi
    
    # Check CronJobs
    local cronjob_count=$(kubectl get cronjobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-manager --no-headers 2>/dev/null | wc -l)
    if [[ $cronjob_count -gt 0 ]]; then
        success "CronJobs created ($cronjob_count total)"
    else
        error "No CronJobs found"
        return 1
    fi
    
    # Check if CronJobs are suspended
    local suspended_count=$(kubectl get cronjobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-manager -o jsonpath='{.items[?(@.spec.suspend==true)].metadata.name}' | wc -w)
    if [[ $suspended_count -eq $cronjob_count ]]; then
        success "All CronJobs are properly suspended"
    else
        warning "Some CronJobs may not be suspended"
    fi
    
    success "Deployment verification complete"
}

show_status() {
    log "Current system status:"
    echo
    
    # Show CronJobs
    echo -e "${BLUE}CronJobs:${NC}"
    kubectl get cronjobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-manager 2>/dev/null || echo "No CronJobs found"
    echo
    
    # Show current deployments
    echo -e "${BLUE}Current Deployments:${NC}"
    kubectl get deployments -n "$NAMESPACE" 2>/dev/null || echo "No deployments found"
    echo
    
    # Show ServiceAccount
    echo -e "${BLUE}RBAC:${NC}"
    kubectl get serviceaccount,role,rolebinding -n "$NAMESPACE" | grep pod-lifecycle 2>/dev/null || echo "No RBAC resources found"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy CronJob-based pod lifecycle management system for resource optimization.

OPTIONS:
    --dry-run       Show what would be deployed without making changes
    --verbose       Enable verbose output
    --help          Show this help message

ENVIRONMENT VARIABLES:
    DRY_RUN         Set to 'true' for dry run mode
    VERBOSE         Set to 'true' for verbose output

EXAMPLES:
    $0                          # Deploy normally
    $0 --dry-run                # Preview deployment
    DRY_RUN=true $0             # Environment variable dry run

NEXT STEPS:
    1. Review deployed CronJobs: kubectl get cronjobs -n $NAMESPACE
    2. Activate lifecycle management: ./scripts/activate_lifecycle.sh
    3. Monitor execution: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-job

SAFETY:
    - All CronJobs start suspended to prevent accidental activation
    - Use activate_lifecycle.sh script to enable pod lifecycle management
    - Emergency rollback available: ./scripts/emergency_rollback.sh
EOF
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    log "Starting Pod Lifecycle Management System deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No changes will be made"
    fi
    
    validate_prerequisites
    deploy_rbac
    deploy_cronjobs
    deploy_monitoring
    
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_deployment
        show_status
    fi
    
    echo
    success "Pod Lifecycle Management System deployment complete!"
    warning "CronJobs are suspended for safety."
    log "Next step: Run './scripts/activate_lifecycle.sh' to enable pod lifecycle management."
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi