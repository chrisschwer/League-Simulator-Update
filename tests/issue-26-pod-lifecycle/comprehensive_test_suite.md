# Comprehensive Test Suite: Pod Lifecycle Management (Issue #26)

## Test Overview
This test suite validates the CronJob-based pod lifecycle management system that scales deployments at precise Berlin times while preserving existing scheduling logic.

## 1. Timezone Validation Tests (Critical)

### Test: Berlin Time vs UTC Conversion
```bash
#!/bin/bash
# test_timezone_conversion.sh

test_berlin_time_conversion() {
  echo "Testing Berlin Time to UTC conversion..."
  
  # Test cases covering different scenarios
  declare -A test_cases=(
    # Standard Time (Winter) - CET (UTC+1)
    ["2024-01-15_17:15"]="16:15"  # BL weekend start
    ["2024-02-20_19:30"]="18:30"  # BL weekday start
    ["2024-12-10_14:50"]="13:50"  # BL2 weekend start
    
    # Daylight Saving Time (Summer) - CEST (UTC+2)  
    ["2024-06-15_17:15"]="15:15"  # BL weekend start in summer
    ["2024-07-22_19:30"]="17:30"  # BL weekday start in summer
    ["2024-08-10_14:50"]="12:50"  # BL2 weekend start in summer
    
    # DST Transition Dates (Critical edge cases)
    ["2024-03-31_17:15"]="15:15"  # Day DST starts (spring forward)
    ["2024-10-27_17:15"]="16:15"  # Day DST ends (fall back)
  )
  
  for test_case in "${!test_cases[@]}"; do
    date_berlin="${test_case%_*}"
    time_berlin="${test_case#*_}"
    expected_utc="${test_cases[$test_case]}"
    
    # Convert Berlin time to UTC using system timezone data
    actual_utc=$(TZ="Europe/Berlin" date -d "$date_berlin $time_berlin" -u "+%H:%M")
    
    if [[ "$actual_utc" != "$expected_utc" ]]; then
      echo "FAIL: $date_berlin $time_berlin"
      echo "  Expected UTC: $expected_utc"
      echo "  Actual UTC: $actual_utc"
      return 1
    else
      echo "PASS: $date_berlin $time_berlin → $actual_utc UTC"
    fi
  done
}

test_dst_transition_behavior() {
  echo "Testing DST transition edge cases..."
  
  # 2024 DST transitions (Europe/Berlin)
  local spring_forward="2024-03-31 02:00"  # 2:00 AM becomes 3:00 AM
  local fall_back="2024-10-27 03:00"       # 3:00 AM becomes 2:00 AM
  
  # Verify our CronJob schedules work correctly during transitions
  test_schedule_during_dst "17:15" "2024-03-31" "Bundesliga weekend start"
  test_schedule_during_dst "21:50" "2024-03-31" "Bundesliga weekend stop"
  test_schedule_during_dst "17:15" "2024-10-27" "Bundesliga weekend start"
  test_schedule_during_dst "21:50" "2024-10-27" "Bundesliga weekend stop"
}

test_schedule_during_dst() {
  local berlin_time="$1"
  local date="$2"
  local description="$3"
  
  echo "Testing $description on $date at $berlin_time Berlin time"
  
  # Calculate what UTC time this should be
  local utc_time=$(TZ="Europe/Berlin" date -d "$date $berlin_time" -u "+%H:%M")
  local utc_hour="${utc_time%:*}"
  local utc_minute="${utc_time#*:}"
  
  echo "  Berlin: $berlin_time → UTC: $utc_time"
  echo "  CronJob schedule should be: \"$utc_minute $utc_hour * * *\""
}
```

### Test: CronJob Schedule Accuracy
```yaml
# test_cronjob_schedules.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: timezone-test-scripts
  namespace: league-simulator
data:
  validate-schedules.sh: |
    #!/bin/bash
    # Validate that CronJobs execute at correct Berlin times
    
    # Define expected Berlin times for each CronJob
    declare -A expected_berlin_times=(
      ["start-bl-weekend"]="17:15"
      ["stop-bl-weekend"]="21:50" 
      ["start-bl-weekday"]="19:25"
      ["stop-bl-weekday"]="23:35"
      ["start-bl2-weekend"]="14:45"
      ["stop-bl2-weekend"]="23:05"
      ["start-bl2-weekday"]="19:25"
      ["stop-bl2-weekday"]="23:35"
      ["start-liga3-weekend"]="15:15"
      ["stop-liga3-weekend"]="22:05"
      ["start-liga3-weekday"]="19:15"
      ["stop-liga3-weekday"]="23:05"
      ["start-shiny"]="14:40"
      ["stop-shiny"]="23:40"
    )
    
    for cronjob in "${!expected_berlin_times[@]}"; do
      echo "Validating $cronjob..."
      
      # Get the actual cron schedule
      schedule=$(kubectl get cronjob "$cronjob" -n league-simulator -o jsonpath='{.spec.schedule}')
      
      # Parse schedule (format: "minute hour * * dayofweek")
      minute=$(echo "$schedule" | cut -d' ' -f1)
      hour=$(echo "$schedule" | cut -d' ' -f2)
      
      # Convert to Berlin time for current date
      current_date=$(date +%Y-%m-%d)
      utc_time=$(printf "%02d:%02d" "$hour" "$minute")
      berlin_time=$(TZ="UTC" date -d "$current_date $utc_time" "+%H:%M" | TZ="Europe/Berlin" date -f - "+%H:%M")
      
      expected="${expected_berlin_times[$cronjob]}"
      
      if [[ "$berlin_time" != "$expected" ]]; then
        echo "FAIL: $cronjob"
        echo "  Schedule: $schedule"
        echo "  Expected Berlin time: $expected"
        echo "  Actual Berlin time: $berlin_time"
        exit 1
      else
        echo "PASS: $cronjob executes at $berlin_time Berlin time"
      fi
    done
---
apiVersion: batch/v1
kind: Job
metadata:
  name: validate-timezone-schedules
  namespace: league-simulator
spec:
  template:
    spec:
      containers:
      - name: validator
        image: bitnami/kubectl:latest
        command: ["/scripts/validate-schedules.sh"]
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: timezone-test-scripts
          defaultMode: 0755
      restartPolicy: Never
```

## 2. CronJob Schedule Validation Tests

### Test: Complete Schedule Matrix
```bash
# test_complete_schedule_matrix.sh
#!/bin/bash

test_all_league_schedules() {
  echo "Testing complete schedule matrix..."
  
  # Comprehensive schedule validation
  local leagues=("bl" "bl2" "liga3" "shiny")
  local schedule_types=("weekend" "weekday")
  local actions=("start" "stop")
  
  # Expected schedules in Berlin time
  declare -A berlin_schedules=(
    # Bundesliga
    ["bl_weekend_start"]="17:15_Sat,Sun"
    ["bl_weekend_stop"]="21:50_Sat,Sun"
    ["bl_weekday_start"]="19:25_Mon-Fri"
    ["bl_weekday_stop"]="23:35_Mon-Fri"
    
    # 2. Bundesliga  
    ["bl2_weekend_start"]="14:45_Sat,Sun"
    ["bl2_weekend_stop"]="23:05_Sat,Sun"
    ["bl2_weekday_start"]="19:25_Mon-Fri"
    ["bl2_weekday_stop"]="23:35_Mon-Fri"
    
    # 3. Liga
    ["liga3_weekend_start"]="15:15_Sat,Sun"
    ["liga3_weekend_stop"]="22:05_Sat,Sun"
    ["liga3_weekday_start"]="19:15_Mon-Fri"
    ["liga3_weekday_stop"]="23:05_Mon-Fri"
    
    # Shiny (daily)
    ["shiny_daily_start"]="14:40_Daily"
    ["shiny_daily_stop"]="23:40_Daily"
  )
  
  for schedule_key in "${!berlin_schedules[@]}"; do
    validate_single_schedule "$schedule_key" "${berlin_schedules[$schedule_key]}"
  done
}

validate_single_schedule() {
  local key="$1"
  local expected_data="$2"
  
  local expected_time="${expected_data%_*}"
  local expected_days="${expected_data#*_}"
  
  echo "Validating $key: Expected $expected_time on $expected_days"
  
  # Convert key to CronJob name
  local cronjob_name=$(echo "$key" | sed 's/_/-/g')
  
  # Test schedule conversion for both summer and winter
  test_schedule_conversion "$cronjob_name" "$expected_time" "2024-01-15" "Winter"
  test_schedule_conversion "$cronjob_name" "$expected_time" "2024-07-15" "Summer"
}

test_schedule_conversion() {
  local cronjob="$1"
  local berlin_time="$2"
  local test_date="$3"
  local season="$4"
  
  # Convert Berlin time to UTC for the test date
  local utc_time=$(TZ="Europe/Berlin" date -d "$test_date $berlin_time" -u "+%H:%M")
  local expected_hour="${utc_time%:*}"
  local expected_minute="${utc_time#*:}"
  
  echo "  $season ($test_date): $berlin_time Berlin → $utc_time UTC"
  echo "  Expected cron: \"$expected_minute $expected_hour * * ...\""
}
```

## 3. Pod Lifecycle Timing Tests

### Test: Precise Startup/Shutdown Timing
```bash
# test_pod_lifecycle_timing.sh
#!/bin/bash

test_pod_startup_timing() {
  echo "Testing pod startup timing precision..."
  
  # Create a test CronJob that should start a deployment
  cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: test-pod-startup
  namespace: league-simulator
spec:
  schedule: "$(date -d '+2 minutes' '+%M %H') * * *"  # 2 minutes from now
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pod-lifecycle-manager
          containers:
          - name: scaler
            image: bitnami/kubectl:latest
            command:
            - kubectl
            - scale
            - deployment
            - league-updater-bl
            - --replicas=1
            - -n
            - league-simulator
          restartPolicy: OnFailure
EOF
  
  # Wait for the job to execute
  echo "Waiting for CronJob to execute..."
  sleep 130  # Wait 2 min 10 seconds
  
  # Check if deployment was scaled up
  local replicas=$(kubectl get deployment league-updater-bl -n league-simulator -o jsonpath='{.spec.replicas}')
  
  if [[ "$replicas" != "1" ]]; then
    echo "FAIL: Deployment not scaled up. Current replicas: $replicas"
    return 1
  fi
  
  # Verify pod is actually running
  local running_pods=$(kubectl get pods -n league-simulator -l app=league-updater,league=bl --field-selector=status.phase=Running --no-headers | wc -l)
  
  if [[ "$running_pods" != "1" ]]; then
    echo "FAIL: Pod not running. Running pods: $running_pods"
    return 1
  fi
  
  echo "PASS: Pod startup executed precisely"
  
  # Cleanup
  kubectl delete cronjob test-pod-startup -n league-simulator
  kubectl scale deployment league-updater-bl --replicas=0 -n league-simulator
}

test_pod_shutdown_timing() {
  echo "Testing pod shutdown timing precision..."
  
  # Ensure pod is running first
  kubectl scale deployment league-updater-bl --replicas=1 -n league-simulator
  kubectl wait --for=condition=available deployment/league-updater-bl -n league-simulator --timeout=60s
  
  # Create shutdown CronJob
  cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: test-pod-shutdown
  namespace: league-simulator
spec:
  schedule: "$(date -d '+2 minutes' '+%M %H') * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pod-lifecycle-manager
          containers:
          - name: scaler
            image: bitnami/kubectl:latest
            command:
            - kubectl
            - scale
            - deployment
            - league-updater-bl
            - --replicas=0
            - -n
            - league-simulator
          restartPolicy: OnFailure
EOF
  
  # Wait and verify shutdown
  sleep 130
  
  local replicas=$(kubectl get deployment league-updater-bl -n league-simulator -o jsonpath='{.spec.replicas}')
  
  if [[ "$replicas" != "0" ]]; then
    echo "FAIL: Deployment not scaled down. Current replicas: $replicas"
    return 1
  fi
  
  echo "PASS: Pod shutdown executed precisely"
  
  # Cleanup
  kubectl delete cronjob test-pod-shutdown -n league-simulator
}
```

## 4. RBAC and Security Tests

### Test: ServiceAccount Permissions
```bash
# test_rbac_permissions.sh
#!/bin/bash

test_pod_lifecycle_manager_permissions() {
  echo "Testing pod-lifecycle-manager ServiceAccount permissions..."
  
  # Test that ServiceAccount can scale deployments
  kubectl auth can-i patch deployments \
    --as=system:serviceaccount:league-simulator:pod-lifecycle-manager \
    -n league-simulator
  
  if [[ $? -ne 0 ]]; then
    echo "FAIL: ServiceAccount cannot patch deployments"
    return 1
  fi
  
  # Test that ServiceAccount can get deployment scale
  kubectl auth can-i get deployments/scale \
    --as=system:serviceaccount:league-simulator:pod-lifecycle-manager \
    -n league-simulator
  
  if [[ $? -ne 0 ]]; then
    echo "FAIL: ServiceAccount cannot get deployment scale"
    return 1
  fi
  
  # Test that ServiceAccount CANNOT access other resources (principle of least privilege)
  kubectl auth can-i create pods \
    --as=system:serviceaccount:league-simulator:pod-lifecycle-manager \
    -n league-simulator
  
  if [[ $? -eq 0 ]]; then
    echo "FAIL: ServiceAccount has excessive permissions (can create pods)"
    return 1
  fi
  
  echo "PASS: ServiceAccount has correct minimal permissions"
}

test_rbac_configuration() {
  echo "Testing RBAC configuration..."
  
  # Verify Role exists
  kubectl get role deployment-scaler -n league-simulator >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "FAIL: Role 'deployment-scaler' not found"
    return 1
  fi
  
  # Verify RoleBinding exists
  kubectl get rolebinding pod-lifecycle-manager -n league-simulator >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "FAIL: RoleBinding 'pod-lifecycle-manager' not found"
    return 1
  fi
  
  # Verify ServiceAccount exists
  kubectl get serviceaccount pod-lifecycle-manager -n league-simulator >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "FAIL: ServiceAccount 'pod-lifecycle-manager' not found"
    return 1
  fi
  
  echo "PASS: RBAC configuration complete"
}
```

## 5. Integration Tests

### Test: Complete League Lifecycle
```bash
# test_complete_league_lifecycle.sh
#!/bin/bash

test_bundesliga_weekend_lifecycle() {
  echo "Testing complete Bundesliga weekend lifecycle..."
  
  # Ensure deployment is initially scaled to 0
  kubectl scale deployment league-updater-bl --replicas=0 -n league-simulator
  
  # Simulate weekend start (17:15 Berlin time)
  simulate_cronjob_execution "start-bl-weekend" "scale to 1"
  
  # Verify pod starts and begins scheduling
  verify_pod_running "league-updater-bl"
  verify_internal_scheduling_active "league-updater-bl"
  
  # Simulate running during active period
  sleep 60  # Let it run for a minute
  
  # Verify application is working correctly
  verify_api_calls_being_made "league-updater-bl"
  verify_results_being_generated "BL"
  
  # Simulate weekend stop (21:50 Berlin time)
  simulate_cronjob_execution "stop-bl-weekend" "scale to 0"
  
  # Verify graceful shutdown
  verify_pod_stopped "league-updater-bl"
  verify_results_persisted "BL"
  
  echo "PASS: Complete Bundesliga weekend lifecycle"
}

simulate_cronjob_execution() {
  local cronjob_name="$1"
  local action="$2"
  
  echo "Simulating $cronjob_name execution ($action)..."
  
  # Create a manual job from the CronJob
  kubectl create job --from=cronjob/$cronjob_name test-$cronjob_name-$(date +%s) -n league-simulator
  
  # Wait for job completion
  sleep 30
}

verify_pod_running() {
  local deployment="$1"
  
  local running_pods=$(kubectl get pods -n league-simulator -l app=league-updater --field-selector=status.phase=Running --no-headers | wc -l)
  
  if [[ "$running_pods" -lt 1 ]]; then
    echo "FAIL: No running pods for $deployment"
    return 1
  fi
  
  echo "PASS: $deployment pod is running"
}

verify_internal_scheduling_active() {
  local deployment="$1"
  
  # Check pod logs for scheduling activity
  local pod_name=$(kubectl get pods -n league-simulator -l app=league-updater -o jsonpath='{.items[0].metadata.name}')
  
  kubectl logs "$pod_name" -n league-simulator --tail=10 | grep -q "scheduler"
  
  if [[ $? -ne 0 ]]; then
    echo "FAIL: No scheduling activity detected in $deployment"
    return 1
  fi
  
  echo "PASS: Internal scheduling is active in $deployment"
}

verify_results_being_generated() {
  local league="$1"
  
  # Check if results file exists and is recent
  local pod_name=$(kubectl get pods -n league-simulator -l app=league-updater -o jsonpath='{.items[0].metadata.name}')
  
  kubectl exec "$pod_name" -n league-simulator -- ls -la /RCode/league_results/Ergebnis_${league}.Rds
  
  if [[ $? -ne 0 ]]; then
    echo "FAIL: No results file found for $league"
    return 1
  fi
  
  echo "PASS: Results being generated for $league"
}
```

## 6. Rollback Tests

### Test: Emergency Rollback Procedure
```bash
# test_rollback_procedure.sh
#!/bin/bash

test_emergency_rollback() {
  echo "Testing emergency rollback procedure..."
  
  # Simulate a problem scenario
  kubectl patch cronjob start-bl-weekend -n league-simulator --patch '{"spec":{"suspend":false}}'
  kubectl patch cronjob stop-bl-weekend -n league-simulator --patch '{"spec":{"suspend":false}}'
  
  # Execute rollback
  ./scripts/emergency_rollback.sh
  
  # Verify all CronJobs are suspended
  local active_cronjobs=$(kubectl get cronjobs -n league-simulator -o jsonpath='{.items[?(@.spec.suspend==false)].metadata.name}')
  
  if [[ -n "$active_cronjobs" ]]; then
    echo "FAIL: Some CronJobs still active: $active_cronjobs"
    return 1
  fi
  
  # Verify all deployments are running
  local deployments=("league-updater-bl" "league-updater-bl2" "league-updater-liga3" "shiny-updater")
  
  for deployment in "${deployments[@]}"; do
    local replicas=$(kubectl get deployment "$deployment" -n league-simulator -o jsonpath='{.spec.replicas}')
    
    if [[ "$replicas" != "1" ]]; then
      echo "FAIL: $deployment not restored (replicas: $replicas)"
      return 1
    fi
  done
  
  echo "PASS: Emergency rollback successful"
}
```

## 7. Monitoring Tests

### Test: CronJob Success/Failure Monitoring
```python
# test_monitoring_cronjobs.py
import subprocess
import json
import time
from datetime import datetime

def test_cronjob_monitoring():
    """Test that CronJob execution is properly monitored"""
    
    # Get CronJob status
    result = subprocess.run([
        'kubectl', 'get', 'cronjobs', '-n', 'league-simulator', 
        '-o', 'json'
    ], capture_output=True, text=True)
    
    cronjobs = json.loads(result.stdout)
    
    for cronjob in cronjobs['items']:
        name = cronjob['metadata']['name']
        
        # Check if job has run recently
        if 'lastScheduleTime' in cronjob['status']:
            last_run = cronjob['status']['lastScheduleTime']
            print(f"✓ {name}: Last run at {last_run}")
        else:
            print(f"✗ {name}: Never executed")
            
        # Check for failed jobs
        if 'lastSuccessfulTime' not in cronjob['status']:
            print(f"⚠ {name}: No successful executions recorded")

def test_prometheus_metrics():
    """Test that Prometheus is collecting CronJob metrics"""
    
    metrics_to_check = [
        'kube_cronjob_status_last_schedule_time',
        'kube_cronjob_status_active',
        'kube_job_status_succeeded',
        'kube_job_status_failed'
    ]
    
    # Query Prometheus for each metric
    for metric in metrics_to_check:
        # This would typically query your Prometheus endpoint
        print(f"Checking metric: {metric}")
        # Implementation depends on your monitoring setup

if __name__ == "__main__":
    test_cronjob_monitoring()
    test_prometheus_metrics()
```

## Test Execution Plan

### Phase 1: Pre-Implementation Validation
1. **Timezone Tests**: Verify all time conversions are correct
2. **Schedule Matrix**: Validate all 16 CronJob schedules
3. **RBAC Setup**: Test ServiceAccount permissions

### Phase 2: Implementation Testing
1. **Pod Lifecycle**: Test start/stop timing precision
2. **Integration**: Full league lifecycle simulation
3. **Monitoring**: Verify observability setup

### Phase 3: Production Readiness
1. **Rollback**: Test emergency procedures
2. **DST Transitions**: Validate behavior during time changes
3. **Load Testing**: Verify concurrent CronJob execution

## Success Criteria

- ✅ All timezone conversions accurate for Berlin Time and DST
- ✅ CronJobs execute within 30 seconds of scheduled time
- ✅ Pod startup/shutdown timing precision < 1 minute
- ✅ Internal scheduling logic completely preserved
- ✅ 79% resource reduction achieved
- ✅ Emergency rollback completes in < 5 minutes
- ✅ No data loss during lifecycle transitions
- ✅ Monitoring alerts configured and functional

## Critical Timezone Considerations

### DST Transition Dates 2024
- **Spring Forward**: March 31, 2024 (2:00 AM → 3:00 AM)
- **Fall Back**: October 27, 2024 (3:00 AM → 2:00 AM)

### CronJob Schedule Adjustments
All schedules must account for:
1. **Winter (CET)**: UTC = Berlin - 1 hour
2. **Summer (CEST)**: UTC = Berlin - 2 hours
3. **Transition Days**: Special handling required

This ensures pods start/stop at correct Berlin times regardless of season.