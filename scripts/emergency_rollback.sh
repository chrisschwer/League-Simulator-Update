#!/bin/bash
# Emergency Rollback: Pod Lifecycle Management
# Immediately disables CronJob-based scaling and restores always-on deployments

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

emergency_rollback() {
    log "🚨 EMERGENCY ROLLBACK: Disabling pod lifecycle management"
    warning "This will restore the system to always-on state"
    echo
    
    # Step 1: Suspend all CronJobs immediately
    log "Step 1/5: Suspending all CronJobs..."
    local cronjobs_suspended=0
    while IFS= read -r cronjob; do
        if [[ -n "$cronjob" ]]; then
            log "Suspending CronJob: $cronjob"
            kubectl patch cronjob "$cronjob" -n "$NAMESPACE" --patch '{"spec":{"suspend":true}}' || warning "Failed to suspend $cronjob"
            ((cronjobs_suspended++))
        fi
    done < <(kubectl get cronjobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-manager -o jsonpath='{.items[].metadata.name}' 2>/dev/null)
    
    success "Suspended $cronjobs_suspended CronJobs"
    
    # Step 2: Scale all deployments to 1 replica
    log "Step 2/5: Restoring all deployments..."
    local deployments=("league-updater-bl" "league-updater-bl2" "league-updater-liga3" "shiny-updater")
    local deployments_restored=0
    
    for deployment in "${deployments[@]}"; do
        if kubectl get deployment "$deployment" -n "$NAMESPACE" &> /dev/null; then
            log "Scaling $deployment to 1 replica..."
            kubectl scale deployment "$deployment" --replicas=1 -n "$NAMESPACE" || warning "Failed to scale $deployment"
            ((deployments_restored++))
        else
            warning "Deployment $deployment not found, skipping"
        fi
    done
    
    success "Restored $deployments_restored deployments"
    
    # Step 3: Wait for all pods to be ready
    log "Step 3/5: Waiting for pods to be ready..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    local all_ready=false
    
    while [[ $wait_time -lt $max_wait ]] && [[ "$all_ready" == "false" ]]; do
        all_ready=true
        for deployment in "${deployments[@]}"; do
            if kubectl get deployment "$deployment" -n "$NAMESPACE" &> /dev/null; then
                local ready=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
                local desired=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
                
                if [[ "$ready" != "$desired" ]]; then
                    all_ready=false
                    break
                fi
            fi
        done
        
        if [[ "$all_ready" == "false" ]]; then
            sleep 10
            wait_time=$((wait_time + 10))
            log "Waiting for pods... ($wait_time/${max_wait}s)"
        fi
    done
    
    if [[ "$all_ready" == "true" ]]; then
        success "All pods are ready"
    else
        warning "Some pods may still be starting up (timeout reached)"
    fi
    
    # Step 4: Delete any running lifecycle jobs
    log "Step 4/5: Cleaning up lifecycle jobs..."
    local jobs_deleted=0
    while IFS= read -r job; do
        if [[ -n "$job" ]]; then
            log "Deleting job: $job"
            kubectl delete job "$job" -n "$NAMESPACE" || warning "Failed to delete job $job"
            ((jobs_deleted++))
        fi
    done < <(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-job -o jsonpath='{.items[].metadata.name}' 2>/dev/null)
    
    success "Deleted $jobs_deleted lifecycle jobs"
    
    # Step 5: Verify system status
    log "Step 5/5: Verifying system status..."
    verify_rollback_success
    
    echo
    success "🎉 Emergency rollback complete!"
    log "System restored to always-on state."
}

verify_rollback_success() {
    local issues=0
    
    # Check deployments
    log "Verifying deployments..."
    local deployments=("league-updater-bl" "league-updater-bl2" "league-updater-liga3" "shiny-updater")
    for deployment in "${deployments[@]}"; do
        if kubectl get deployment "$deployment" -n "$NAMESPACE" &> /dev/null; then
            local replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            local ready=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            
            if [[ "$replicas" != "1" ]]; then
                error "$deployment not scaled to 1 (current: $replicas)"
                ((issues++))
            elif [[ "$ready" != "1" ]]; then
                warning "$deployment not ready (ready: $ready/1)"
                ((issues++))
            else
                success "$deployment: 1/1 ready"
            fi
        else
            warning "$deployment not found"
            ((issues++))
        fi
    done
    
    # Check CronJobs
    log "Verifying CronJobs are suspended..."
    local active_cronjobs=$(kubectl get cronjobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-manager -o jsonpath='{.items[?(@.spec.suspend==false)].metadata.name}' 2>/dev/null)
    
    if [[ -n "$active_cronjobs" ]]; then
        error "Some CronJobs are still active: $active_cronjobs"
        ((issues++))
    else
        success "All CronJobs suspended"
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "Rollback verification passed"
    else
        warning "Rollback completed with $issues issues"
        return 1
    fi
}

show_system_status() {
    log "Current system status:"
    echo
    
    # Show deployments
    echo -e "${BLUE}Deployments:${NC}"
    kubectl get deployments -n "$NAMESPACE" -o custom-columns="NAME:.metadata.name,REPLICAS:.spec.replicas,READY:.status.readyReplicas,AGE:.metadata.creationTimestamp" 2>/dev/null || echo "No deployments found"
    echo
    
    # Show CronJobs
    echo -e "${BLUE}CronJobs:${NC}"
    kubectl get cronjobs -n "$NAMESPACE" -l app.kubernetes.io/name=pod-lifecycle-manager -o custom-columns="NAME:.metadata.name,SCHEDULE:.spec.schedule,SUSPENDED:.spec.suspend" 2>/dev/null || echo "No CronJobs found"
    echo
    
    # Show running pods
    echo -e "${BLUE}Running Pods:${NC}"
    kubectl get pods -n "$NAMESPACE" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,AGE:.metadata.creationTimestamp" 2>/dev/null || echo "No pods found"
}

show_next_steps() {
    log "Next Steps and Options:"
    echo
    
    cat << EOF
✅ SYSTEM RESTORED: All deployments are now running 24/7

🔄 TO RE-ENABLE POD LIFECYCLE (if issues resolved):
   ./scripts/activate_lifecycle.sh

🔍 TROUBLESHOOTING:
   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-job --tail=100
   kubectl describe cronjobs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-manager

🗑️  COMPLETE REMOVAL (if no longer needed):
   kubectl delete cronjobs -n $NAMESPACE -l app.kubernetes.io/name=pod-lifecycle-manager
   kubectl delete serviceaccount,role,rolebinding pod-lifecycle-manager -n $NAMESPACE

📊 RESOURCE MONITORING:
   kubectl top pods -n $NAMESPACE
   kubectl get deployments -n $NAMESPACE

💡 The system is now in the original always-on state with no automatic scaling.
EOF
    echo
}

confirm_emergency_rollback() {
    warning "🚨 EMERGENCY ROLLBACK CONFIRMATION"
    echo
    echo "This will immediately:"
    echo "• Suspend all pod lifecycle CronJobs"
    echo "• Scale all deployments back to 1 replica (always-on)"
    echo "• Delete any running lifecycle jobs"
    echo "• Restore the system to its original state"
    echo
    echo "Current system status:"
    kubectl get deployments -n "$NAMESPACE" -o custom-columns="NAME:.metadata.name,REPLICAS:.spec.replicas" 2>/dev/null || echo "No deployments found"
    echo
    
    read -p "Continue with emergency rollback? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Emergency rollback cancelled by user"
        exit 0
    fi
}

main() {
    log "Emergency Rollback: Pod Lifecycle Management"
    echo
    
    confirm_emergency_rollback
    emergency_rollback
    show_system_status
    show_next_steps
    
    echo
    success "Emergency rollback completed successfully! ✅"
    warning "System is now back to always-on state."
}

main "$@"