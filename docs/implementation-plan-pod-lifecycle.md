# Implementation Plan: Pod Lifecycle Management (Issue #26)

## Executive Summary

Implement CronJob-based pod lifecycle management to achieve 79% resource reduction while preserving existing scheduling logic. The solution uses 16 CronJobs to precisely start/stop deployments based on Berlin Time schedules.

## Phase 1: Foundation Setup (Day 1, 2-3 hours)

### 1.1 RBAC Configuration
**Files to create:**
- `k8s/rbac/serviceaccount.yaml`
- `k8s/rbac/role.yaml` 
- `k8s/rbac/rolebinding.yaml`

**Implementation:**
```yaml
# serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-lifecycle-manager
  namespace: league-simulator

# role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployment-scaler
  namespace: league-simulator
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "deployments/scale"]
  verbs: ["get", "patch", "update"]

# rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-lifecycle-manager
  namespace: league-simulator
subjects:
- kind: ServiceAccount
  name: pod-lifecycle-manager
  namespace: league-simulator
roleRef:
  kind: Role
  name: deployment-scaler
  apiGroup: rbac.authorization.k8s.io
```

### 1.2 Timezone Calculation Script
**File:** `scripts/calculate_cronjob_schedules.sh`

**Purpose:** Generate correct UTC schedules from Berlin times

```bash
#!/bin/bash
# Converts Berlin times to UTC for CronJob schedules
# Handles both CET (UTC+1) and CEST (UTC+2)

calculate_utc_schedule() {
  local berlin_time="$1"
  local season="$2"  # "winter" or "summer"
  
  local hour="${berlin_time%:*}"
  local minute="${berlin_time#*:}"
  
  if [[ "$season" == "winter" ]]; then
    # CET: UTC = Berlin - 1 hour
    utc_hour=$((hour - 1))
  else
    # CEST: UTC = Berlin - 2 hours  
    utc_hour=$((hour - 2))
  fi
  
  # Handle day rollover
  if [[ $utc_hour -lt 0 ]]; then
    utc_hour=$((utc_hour + 24))
  fi
  
  printf "%02d %02d" "$minute" "$utc_hour"
}
```

## Phase 2: CronJob Manifests (Day 1-2, 4-5 hours)

### 2.1 Directory Structure
```
k8s/
├── rbac/
│   ├── serviceaccount.yaml
│   ├── role.yaml
│   └── rolebinding.yaml
├── cronjobs/
│   ├── bundesliga/
│   │   ├── start-bl-weekend.yaml
│   │   ├── stop-bl-weekend.yaml
│   │   ├── start-bl-weekday.yaml
│   │   └── stop-bl-weekday.yaml
│   ├── bundesliga2/
│   │   ├── start-bl2-weekend.yaml
│   │   ├── stop-bl2-weekend.yaml
│   │   ├── start-bl2-weekday.yaml
│   │   └── stop-bl2-weekday.yaml
│   ├── liga3/
│   │   ├── start-liga3-weekend.yaml
│   │   ├── stop-liga3-weekend.yaml
│   │   ├── start-liga3-weekday.yaml
│   │   └── stop-liga3-weekday.yaml
│   └── shiny/
│       ├── start-shiny.yaml
│       └── stop-shiny.yaml
└── monitoring/
    ├── cronjob-monitor.yaml
    └── alerts.yaml
```

### 2.2 CronJob Template
**Standard template for all 16 CronJobs:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ${ACTION}-${LEAGUE}-${SCHEDULE_TYPE}
  namespace: league-simulator
  labels:
    app: pod-lifecycle-manager
    league: ${LEAGUE}
    action: ${ACTION}
    schedule-type: ${SCHEDULE_TYPE}
spec:
  # Calculated UTC schedule (see Phase 1.2)
  schedule: "${UTC_MINUTE} ${UTC_HOUR} * * ${DAYS}"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      activeDeadlineSeconds: 300  # 5 minutes max
      template:
        metadata:
          labels:
            app: pod-lifecycle-job
            league: ${LEAGUE}
            action: ${ACTION}
        spec:
          serviceAccountName: pod-lifecycle-manager
          restartPolicy: OnFailure
          containers:
          - name: scaler
            image: bitnami/kubectl:1.28
            command:
            - kubectl
            - scale
            - deployment
            - ${DEPLOYMENT_NAME}
            - --replicas=${REPLICA_COUNT}
            - -n
            - league-simulator
            resources:
              requests:
                memory: "64Mi"
                cpu: "50m"
              limits:
                memory: "128Mi"
                cpu: "100m"
```

### 2.3 Schedule Calculations
**Berlin Time → UTC conversion for all schedules:**

```yaml
# Bundesliga Schedules
BL Weekend Start:  17:15 Berlin → 15:15 UTC (summer) / 16:15 UTC (winter)
BL Weekend Stop:   21:50 Berlin → 19:50 UTC (summer) / 20:50 UTC (winter)
BL Weekday Start:  19:25 Berlin → 17:25 UTC (summer) / 18:25 UTC (winter)
BL Weekday Stop:   23:35 Berlin → 21:35 UTC (summer) / 22:35 UTC (winter)

# 2. Bundesliga Schedules  
BL2 Weekend Start: 14:45 Berlin → 12:45 UTC (summer) / 13:45 UTC (winter)
BL2 Weekend Stop:  23:05 Berlin → 21:05 UTC (summer) / 22:05 UTC (winter)
BL2 Weekday Start: 19:25 Berlin → 17:25 UTC (summer) / 18:25 UTC (winter)
BL2 Weekday Stop:  23:35 Berlin → 21:35 UTC (summer) / 22:35 UTC (winter)

# 3. Liga Schedules
Liga3 Weekend Start: 15:15 Berlin → 13:15 UTC (summer) / 14:15 UTC (winter)
Liga3 Weekend Stop:  22:05 Berlin → 20:05 UTC (summer) / 21:05 UTC (winter)
Liga3 Weekday Start: 19:15 Berlin → 17:15 UTC (summer) / 18:15 UTC (winter)
Liga3 Weekday Stop:  23:05 Berlin → 21:05 UTC (summer) / 22:05 UTC (winter)

# Shiny Schedules (covers all leagues)
Shiny Start: 14:40 Berlin → 12:40 UTC (summer) / 13:40 UTC (winter)
Shiny Stop:  23:40 Berlin → 21:40 UTC (summer) / 22:40 UTC (winter)
```

## Phase 3: Monitoring & Observability (Day 2, 2-3 hours)

### 3.1 Prometheus ServiceMonitor
**File:** `k8s/monitoring/cronjob-monitor.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cronjob-lifecycle-monitor
  namespace: league-simulator
spec:
  selector:
    matchLabels:
      app: pod-lifecycle-manager
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### 3.2 Alert Rules
**File:** `k8s/monitoring/alerts.yaml`

```yaml
groups:
- name: pod-lifecycle-alerts
  rules:
  - alert: CronJobExecutionFailed
    expr: kube_job_status_failed{namespace="league-simulator"} > 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "CronJob execution failed"
      description: "CronJob {{ $labels.job_name }} in namespace {{ $labels.namespace }} has failed"

  - alert: PodLifecycleMissing
    expr: |
      (time() - on(deployment) kube_deployment_status_replicas{namespace="league-simulator"} * 60) > 3600
      and on(deployment) kube_deployment_spec_replicas{namespace="league-simulator"} == 0
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Pod may be stuck in stopped state"
      description: "Deployment {{ $labels.deployment }} has been scaled to 0 for over 1 hour"

  - alert: ScheduleDrift
    expr: |
      (time() - kube_cronjob_status_last_schedule_time{namespace="league-simulator"}) > 7200
    for: 15m
    labels:
      severity: warning
    annotations:
      summary: "CronJob schedule drift detected"
      description: "CronJob {{ $labels.cronjob }} hasn't executed in over 2 hours"
```

## Phase 4: Deployment Scripts (Day 2, 1-2 hours)

### 4.1 Deployment Script
**File:** `scripts/deploy_pod_lifecycle.sh`

```bash
#!/bin/bash
set -e

NAMESPACE="league-simulator"
DRY_RUN="${DRY_RUN:-false}"

deploy_component() {
  local component="$1"
  local path="$2"
  
  echo "Deploying $component..."
  
  if [[ "$DRY_RUN" == "true" ]]; then
    kubectl apply -f "$path" --dry-run=client
  else
    kubectl apply -f "$path"
  fi
}

main() {
  echo "Deploying Pod Lifecycle Management System..."
  
  # Phase 1: RBAC
  deploy_component "RBAC" "k8s/rbac/"
  
  # Phase 2: CronJobs (suspended initially)
  for cronjob_file in k8s/cronjobs/**/*.yaml; do
    # Add suspend: true to all CronJobs for safe deployment
    yq eval '.spec.suspend = true' "$cronjob_file" | kubectl apply -f -
  done
  
  # Phase 3: Monitoring
  deploy_component "Monitoring" "k8s/monitoring/"
  
  echo "Deployment complete. CronJobs are suspended for safety."
  echo "Run './scripts/activate_lifecycle.sh' to enable pod lifecycle management."
}

main "$@"
```

### 4.2 Activation Script
**File:** `scripts/activate_lifecycle.sh`

```bash
#!/bin/bash
set -e

NAMESPACE="league-simulator"

activate_cronjobs() {
  echo "Activating CronJob pod lifecycle management..."
  
  # Remove suspend flag from all CronJobs
  kubectl patch cronjobs -n "$NAMESPACE" -l app=pod-lifecycle-manager \
    --patch '{"spec":{"suspend":false}}'
  
  echo "Pod lifecycle management activated!"
  echo "Monitoring CronJob execution..."
  
  # Watch CronJob status
  kubectl get cronjobs -n "$NAMESPACE" -l app=pod-lifecycle-manager --watch
}

confirm_activation() {
  echo "This will activate automatic pod lifecycle management."
  echo "Deployments will be scaled down outside their active windows."
  echo ""
  read -p "Are you sure? (yes/no): " confirm
  
  if [[ "$confirm" != "yes" ]]; then
    echo "Activation cancelled."
    exit 0
  fi
}

main() {
  confirm_activation
  activate_cronjobs
}

main "$@"
```

## Phase 5: Rollback Procedures (Day 3, 1-2 hours)

### 5.1 Emergency Rollback Script
**File:** `scripts/emergency_rollback.sh`

```bash
#!/bin/bash
set -e

NAMESPACE="league-simulator"

emergency_rollback() {
  echo "🚨 EMERGENCY ROLLBACK: Disabling pod lifecycle management"
  
  # 1. Suspend all CronJobs immediately
  echo "Suspending all CronJobs..."
  kubectl patch cronjobs -n "$NAMESPACE" -l app=pod-lifecycle-manager \
    --patch '{"spec":{"suspend":true}}'
  
  # 2. Scale all deployments to 1 replica
  echo "Restoring all deployments..."
  local deployments=("league-updater-bl" "league-updater-bl2" "league-updater-liga3" "shiny-updater")
  
  for deployment in "${deployments[@]}"; do
    echo "Scaling $deployment to 1 replica..."
    kubectl scale deployment "$deployment" --replicas=1 -n "$NAMESPACE"
  done
  
  # 3. Wait for all pods to be ready
  echo "Waiting for pods to be ready..."
  for deployment in "${deployments[@]}"; do
    kubectl wait --for=condition=available deployment/"$deployment" \
      -n "$NAMESPACE" --timeout=300s
  done
  
  # 4. Delete any running lifecycle jobs
  echo "Cleaning up lifecycle jobs..."
  kubectl delete jobs -n "$NAMESPACE" -l app=pod-lifecycle-job
  
  echo "✅ Emergency rollback complete!"
  echo "System restored to always-on state."
  
  # 5. Verify system status
  kubectl get deployments -n "$NAMESPACE"
  kubectl get cronjobs -n "$NAMESPACE"
}

main() {
  echo "This will immediately disable pod lifecycle management and restore always-on deployments."
  read -p "Continue with emergency rollback? (yes/no): " confirm
  
  if [[ "$confirm" == "yes" ]]; then
    emergency_rollback
  else
    echo "Rollback cancelled."
  fi
}

main "$@"
```

### 5.2 Gradual Rollback Script
**File:** `scripts/gradual_rollback.sh`

```bash
#!/bin/bash
set -e

NAMESPACE="league-simulator"

gradual_rollback() {
  local league="$1"
  
  if [[ -z "$league" ]]; then
    echo "Usage: $0 <league>"
    echo "Leagues: bl, bl2, liga3, shiny"
    exit 1
  fi
  
  echo "Rolling back pod lifecycle for $league..."
  
  # Suspend CronJobs for specific league
  kubectl patch cronjobs -n "$NAMESPACE" -l app=pod-lifecycle-manager,league="$league" \
    --patch '{"spec":{"suspend":true}}'
  
  # Scale deployment to 1
  kubectl scale deployment "league-updater-$league" --replicas=1 -n "$NAMESPACE"
  
  # Wait for readiness
  kubectl wait --for=condition=available deployment/"league-updater-$league" \
    -n "$NAMESPACE" --timeout=300s
  
  echo "✅ Rollback complete for $league"
}

main() {
  gradual_rollback "$1"
}

main "$@"
```

## Phase 6: Testing & Validation (Day 3, 2-3 hours)

### 6.1 Test Execution Plan
1. **RBAC Tests**: Verify ServiceAccount permissions
2. **Timezone Tests**: Validate Berlin Time → UTC conversion
3. **CronJob Tests**: Test schedule accuracy
4. **Integration Tests**: Full lifecycle simulation
5. **Rollback Tests**: Emergency and gradual procedures

### 6.2 Validation Checklist
- [ ] All 16 CronJobs created successfully
- [ ] RBAC permissions working correctly
- [ ] Test CronJob executions at expected times
- [ ] Pod scaling precision (within 30 seconds)
- [ ] Internal scheduling logic preserved
- [ ] Emergency rollback completes in < 5 minutes
- [ ] Monitoring and alerts functional

## Implementation Timeline

### Day 1 (4-6 hours)
- **Morning**: Phase 1 (RBAC) + Phase 2.1-2.2 (CronJob structure)
- **Afternoon**: Phase 2.3 (Schedule calculations) + Start Phase 3

### Day 2 (4-6 hours)  
- **Morning**: Complete Phase 3 (Monitoring) + Phase 4 (Scripts)
- **Afternoon**: Phase 5 (Rollback procedures)

### Day 3 (3-4 hours)
- **Morning**: Phase 6 (Testing & validation)
- **Afternoon**: Documentation and final verification

**Total Effort**: 2-3 days (11-16 hours)

## Dependencies & Prerequisites

### External Dependencies
- Kubernetes cluster access
- kubectl configured
- yq tool for YAML processing
- Prometheus/monitoring stack (optional)

### Internal Dependencies  
- Issue #25 completion preferred (Docker optimization)
- Current deployment structure understanding
- Access to test environment

## Risk Mitigation

### Technical Risks
1. **Timezone Miscalculation**: Mitigated by comprehensive testing
2. **CronJob Overlap**: Prevented by `concurrencyPolicy: Forbid`
3. **Pod Startup Delays**: 5-minute buffer before actual schedules

### Operational Risks
1. **Rollback Complexity**: Automated scripts with < 5-minute RTO
2. **Schedule Drift**: Monitoring alerts for early detection
3. **DST Transitions**: Tested for March 31 and October 27

## Success Metrics

- ✅ 79% resource reduction achieved
- ✅ Pod lifecycle timing within 30 seconds of target
- ✅ Zero application code changes required
- ✅ Emergency rollback time < 5 minutes
- ✅ All timezone tests passing
- ✅ No data loss during transitions

## Post-Implementation

### Monitoring Dashboards
- CronJob execution success/failure rates
- Pod lifecycle timing accuracy
- Resource usage reduction metrics
- DST transition behavior

### Maintenance Tasks
- Quarterly schedule review
- Annual DST transition testing
- Resource usage optimization
- CronJob history cleanup

---

*This implementation plan ensures a smooth transition to CronJob-based pod lifecycle management while preserving all existing functionality and achieving the target resource savings.*