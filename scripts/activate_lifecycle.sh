#!/bin/bash
# Activate CronJob-based Pod Lifecycle Management
# Enables automatic pod scaling based on Berlin time schedules

set -e

NAMESPACE="league-simulator"

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

validate_system() {
    log "Validating system before activation..."
    
    # Check if CronJobs exist
    local cronjob_count=$(kubectl get cronjobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-manager --no-headers 2>/dev/null | wc -l)
    if [[ $cronjob_count -eq 0 ]]; then
        error "No CronJobs found. Run './scripts/deploy_pod_lifecycle.sh' first."
        exit 1
    fi
    
    # Check if deployments exist
    local deployments=("league-updater-bl" "league-updater-bl2" "league-updater-liga3" "shiny-updater")
    for deployment in "${deployments[@]}"; do
        if ! kubectl get deployment "$deployment" -n "$NAMESPACE" &> /dev/null; then
            error "Deployment $deployment not found in namespace $NAMESPACE"
            exit 1
        fi
    done
    
    # Check RBAC
    if ! kubectl get serviceaccount pod-lifecycle-manager -n "$NAMESPACE" &> /dev/null; then
        error "ServiceAccount pod-lifecycle-manager not found"
        exit 1
    fi
    
    success "System validation passed"
}

show_current_status() {
    log "Current system status:"
    echo
    
    # Show current deployment replicas
    echo -e "${BLUE}Current Deployment Status:${NC}"
    kubectl get deployments -n "$NAMESPACE" -o custom-columns="NAME:.metadata.name,REPLICAS:.spec.replicas,READY:.status.readyReplicas" 2>/dev/null || echo "No deployments found"
    echo
    
    # Show CronJob suspension status
    echo -e "${BLUE}CronJob Status:${NC}"
    kubectl get cronjobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-manager -o custom-columns="NAME:.metadata.name,SCHEDULE:.spec.schedule,SUSPENDED:.spec.suspend" 2>/dev/null || echo "No CronJobs found"
    echo
}

show_schedule_preview() {
    log "Pod Lifecycle Schedule Preview (Berlin Time):"
    echo
    
    cat << 'EOF'
📅 BUNDESLIGA (BL):
   Weekend: Start 17:15, Stop 21:50 (Sat/Sun)
   Weekday: Start 19:25, Stop 23:35 (Mon-Fri)

📅 2. BUNDESLIGA (BL2):  
   Weekend: Start 14:45, Stop 23:05 (Sat/Sun)
   Weekday: Start 19:25, Stop 23:35 (Mon-Fri)

📅 3. LIGA:
   Weekend: Start 15:15, Stop 22:05 (Sat/Sun)  
   Weekday: Start 19:15, Stop 23:05 (Mon-Fri)

📅 SHINY UPDATER:
   Daily: Start 14:40, Stop 23:40

💡 Resource Savings: ~79% reduction in pod-hours
💡 All times automatically adjusted for DST
EOF
    echo
}

confirm_activation() {
    warning "IMPORTANT: This will activate automatic pod lifecycle management!"
    echo
    echo "This means:"
    echo "• Deployments will be automatically scaled to 0 outside active windows"
    echo "• Pods will start/stop based on Berlin time schedules"
    echo "• Resource usage will be reduced by ~79%"
    echo "• You can rollback anytime with './scripts/emergency_rollback.sh'"
    echo
    
    read -p "Are you sure you want to activate pod lifecycle management? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Activation cancelled by user"
        exit 0
    fi
}

activate_cronjobs() {
    log "Activating CronJob pod lifecycle management..."
    
    # Unsuspend all CronJobs
    local cronjobs_updated=0
    while IFS= read -r cronjob; do
        if [[ -n "$cronjob" ]]; then
            log "Activating CronJob: $cronjob"
            kubectl patch cronjob "$cronjob" -n "$NAMESPACE" --patch '{"spec":{"suspend":false}}'
            ((cronjobs_updated++))
        fi
    done < <(kubectl get cronjobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-manager -o jsonpath='{.items[].metadata.name}')
    
    success "Activated $cronjobs_updated CronJobs"
}

monitor_initial_execution() {
    log "Monitoring initial CronJob execution..."
    warning "This may take a few minutes depending on current time..."
    
    # Wait a moment for CronJobs to potentially trigger
    sleep 30
    
    # Show recent job activity
    log "Recent job activity:"
    kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-job --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -5 || echo "No jobs executed yet"
    
    echo
    log "To monitor ongoing execution:"
    echo "  kubectl get cronjobs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-manager --watch"
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-job --tail=50"
}

show_management_commands() {
    log "Pod Lifecycle Management Commands:"
    echo
    
    cat << EOF
🔍 MONITORING:
   kubectl get cronjobs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-manager
   kubectl get jobs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-job
   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-job --tail=50

⏸️  SUSPEND (Disable temporarily):
   kubectl patch cronjobs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-manager --patch '{"spec":{"suspend":true}}'

▶️  RESUME:
   kubectl patch cronjobs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-manager --patch '{"spec":{"suspend":false}}'

🚨 EMERGENCY ROLLBACK:
   ./scripts/emergency_rollback.sh

📊 CHECK RESOURCE SAVINGS:
   kubectl top pods -n $NAMESPACE
   kubectl get deployments -n $NAMESPACE -o custom-columns="NAME:.metadata.name,REPLICAS:.spec.replicas"
EOF
    echo
}

main() {
    log "Pod Lifecycle Management Activation"
    echo
    
    validate_system
    show_current_status
    show_schedule_preview
    confirm_activation
    
    activate_cronjobs
    monitor_initial_execution
    show_management_commands
    
    echo
    success "Pod Lifecycle Management is now ACTIVE! 🚀"
    warning "Monitor the system for the first few cycles to ensure proper operation."
    log "Emergency rollback is available anytime: './scripts/emergency_rollback.sh'"
}

main "$@"