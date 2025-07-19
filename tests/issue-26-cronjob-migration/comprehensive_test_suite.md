## Comprehensive Test Suite: CronJob Migration

### 1. Unit Tests - R Code Modifications

#### Test: RUN_ONCE Environment Variable Support
```r
# test_run_once_support.R
test_that("league_scheduler exits after single run when RUN_ONCE=true", {
  Sys.setenv(RUN_ONCE = "true")
  
  # Mock functions
  mock_update_league <- mockery::mock(return_value = TRUE)
  mock_is_within_window <- mockery::mock(return_value = TRUE, cycle = TRUE)
  
  # Run scheduler with mocks
  with_mock(
    update_league = mock_update_league,
    is_within_window = mock_is_within_window,
    {
      # Should exit after one iteration
      expect_error(
        league_scheduler(league = "BL", max_daily_calls = 30),
        NA  # No error expected, clean exit
      )
    }
  )
  
  # Verify single execution
  mockery::expect_called(mock_update_league, n = 1)
  
  Sys.unsetenv("RUN_ONCE")
})

test_that("updateScheduler respects RUN_ONCE environment variable", {
  Sys.setenv(RUN_ONCE = "true")
  
  mock_update_all_leagues_loop <- mockery::mock(return_value = TRUE)
  
  with_mock(
    update_all_leagues_loop = mock_update_all_leagues_loop,
    {
      # Should run once and exit
      expect_silent(updateScheduler())
    }
  )
  
  mockery::expect_called(mock_update_all_leagues_loop, n = 1)
  mockery::expect_args(mock_update_all_leagues_loop, 1, loops = 1)
  
  Sys.unsetenv("RUN_ONCE")
})
```

#### Test: Security Token Migration
```r
# test_security_token.R
test_that("updateShiny uses environment variable for token", {
  # Set test environment
  Sys.setenv(SHINYAPPS_IO_TOKEN = "test_token_123")
  Sys.setenv(SHINYAPPS_IO_SECRET = "test_secret")
  
  # Mock rsconnect functions
  mock_setAccountInfo <- mockery::mock()
  mock_deployApp <- mockery::mock()
  
  with_mock(
    `rsconnect::setAccountInfo` = mock_setAccountInfo,
    `rsconnect::deployApp` = mock_deployApp,
    {
      updateShiny(Ergebnis = list(), Ergebnis2 = list(), Ergebnis3 = list())
    }
  )
  
  # Verify token from environment was used
  mockery::expect_args(
    mock_setAccountInfo, 1,
    name = "chrisschwer",
    token = "test_token_123",
    secret = "test_secret"
  )
  
  Sys.unsetenv(c("SHINYAPPS_IO_TOKEN", "SHINYAPPS_IO_SECRET"))
})

test_that("updateShiny fails gracefully without token", {
  Sys.unsetenv("SHINYAPPS_IO_TOKEN")
  
  expect_error(
    updateShiny(Ergebnis = list(), Ergebnis2 = list(), Ergebnis3 = list()),
    "SHINYAPPS_IO_TOKEN environment variable not set"
  )
})
```

### 2. Integration Tests - Kubernetes Manifests

#### Test: CronJob YAML Validation
```bash
# test_cronjob_validation.sh
#!/bin/bash

test_cronjob_yaml_validity() {
  # Validate each CronJob YAML
  for cronjob in k8s/cronjobs/*.yaml; do
    echo "Validating $cronjob"
    kubectl --dry-run=client apply -f "$cronjob" || return 1
  done
}

test_cron_expressions() {
  # Test cron expression parsing
  declare -A expected_schedules=(
    ["bl-weekend"]="20 17-21 * * 0,6"
    ["bl-weekday"]="30 19-23 * * 1-5"
    ["bl2-weekend"]="50 14-22 * * 0,6"
    ["bl2-weekday"]="30 19-23 * * 1-5"
    ["liga3-weekend"]="20 15-21 * * 0,6"
    ["liga3-weekday"]="20 19-22 * * 1-5"
    ["shiny-start"]="45 14 * * *"
    ["shiny-stop"]="35 23 * * *"
  )
  
  for cronjob in "${!expected_schedules[@]}"; do
    actual=$(yq eval '.spec.schedule' "k8s/cronjobs/${cronjob}.yaml")
    expected="${expected_schedules[$cronjob]}"
    
    if [[ "$actual" != "$expected" ]]; then
      echo "FAIL: $cronjob schedule mismatch"
      echo "  Expected: $expected"
      echo "  Actual: $actual"
      return 1
    fi
  done
  
  echo "All cron expressions valid"
}

test_resource_limits() {
  # Verify resource configurations
  for cronjob in k8s/cronjobs/league-*.yaml; do
    memory_limit=$(yq eval '.spec.jobTemplate.spec.template.spec.containers[0].resources.limits.memory' "$cronjob")
    memory_request=$(yq eval '.spec.jobTemplate.spec.template.spec.containers[0].resources.requests.memory' "$cronjob")
    cpu_limit=$(yq eval '.spec.jobTemplate.spec.template.spec.containers[0].resources.limits.cpu' "$cronjob")
    
    # League jobs should have no CPU limit
    if [[ "$cpu_limit" != "null" ]]; then
      echo "FAIL: $cronjob should not have CPU limit"
      return 1
    fi
    
    # Check memory settings
    if [[ "$memory_limit" != "512Mi" ]] || [[ "$memory_request" != "256Mi" ]]; then
      echo "FAIL: $cronjob incorrect memory configuration"
      return 1
    fi
  done
}
```

### 3. End-to-End Tests - Complete Migration

#### Test: Shadow Deployment Validation
```bash
# test_shadow_deployment.sh
#!/bin/bash

test_shadow_deployment() {
  # Deploy CronJobs in suspended mode
  kubectl apply -f k8s/cronjobs/ --namespace=league-simulator
  kubectl patch cronjob -n league-simulator -l app=league-updater \
    --patch '{"spec":{"suspend":true}}'
  
  # Verify both Deployments and CronJobs exist
  deployment_count=$(kubectl get deployments -n league-simulator --no-headers | wc -l)
  cronjob_count=$(kubectl get cronjobs -n league-simulator --no-headers | wc -l)
  
  if [[ $deployment_count -ne 4 ]] || [[ $cronjob_count -ne 8 ]]; then
    echo "FAIL: Expected 4 deployments and 8 cronjobs"
    return 1
  fi
  
  # Test manual job execution
  kubectl create job --from=cronjob/league-updater-bl-weekend test-bl-weekend \
    -n league-simulator
  
  # Wait for completion
  kubectl wait --for=condition=complete job/test-bl-weekend \
    -n league-simulator --timeout=300s
  
  # Check exit code
  exit_code=$(kubectl get job test-bl-weekend -n league-simulator \
    -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')
  
  if [[ "$exit_code" != "True" ]]; then
    echo "FAIL: Test job did not complete successfully"
    return 1
  fi
}
```

### 4. Performance Tests

#### Test: Startup Time Measurement
```r
# test_startup_performance.R
test_that("Single-run execution completes within 30 minutes", {
  start_time <- Sys.time()
  
  # Set environment for single run
  Sys.setenv(RUN_ONCE = "true")
  Sys.setenv(RAPIDAPI_KEY = Sys.getenv("TEST_RAPIDAPI_KEY"))
  
  # Run update for one league
  result <- tryCatch(
    update_league(league = "BL", loops = 1, n = 1000),
    error = function(e) NULL
  )
  
  end_time <- Sys.time()
  duration <- as.numeric(difftime(end_time, start_time, units = "mins"))
  
  expect_true(!is.null(result), "Update should complete successfully")
  expect_lt(duration, 30, "Execution should complete within 30 minutes")
  
  Sys.unsetenv("RUN_ONCE")
})
```

### 5. Rollback Tests

#### Test: Automated Rollback Procedure
```bash
# test_rollback.sh
#!/bin/bash

test_rollback_procedure() {
  # Simulate migration
  kubectl scale deployment -n league-simulator \
    league-updater-bl league-updater-bl2 league-updater-liga3 --replicas=0
  
  # Enable CronJobs
  kubectl patch cronjob -n league-simulator -l app=league-updater \
    --patch '{"spec":{"suspend":false}}'
  
  # Simulate failure - suspend CronJobs
  kubectl patch cronjob -n league-simulator -l app=league-updater \
    --patch '{"spec":{"suspend":true}}'
  
  # Execute rollback
  ./scripts/rollback_to_deployments.sh
  
  # Verify deployments are running
  running_pods=$(kubectl get pods -n league-simulator \
    -l app=league-updater --field-selector=status.phase=Running \
    --no-headers | wc -l)
  
  if [[ $running_pods -lt 3 ]]; then
    echo "FAIL: Not all deployments restored"
    return 1
  fi
  
  # Verify CronJobs are suspended
  active_cronjobs=$(kubectl get cronjobs -n league-simulator \
    -o jsonpath='{.items[?(@.spec.suspend==false)].metadata.name}')
  
  if [[ -n "$active_cronjobs" ]]; then
    echo "FAIL: CronJobs not properly suspended"
    return 1
  fi
}
```

### 6. Monitoring Tests

#### Test: Prometheus Metrics
```python
# test_monitoring_metrics.py
import requests
import pytest
from datetime import datetime, timedelta

def test_job_success_metrics():
    """Verify job success rate metrics are collected"""
    prometheus_url = "http://prometheus:9090"
    
    # Query for job success rate
    query = 'rate(kube_job_status_succeeded{namespace="league-simulator"}[5m])'
    response = requests.get(f"{prometheus_url}/api/v1/query", params={"query": query})
    
    assert response.status_code == 200
    data = response.json()
    assert len(data['data']['result']) > 0

def test_alert_rules():
    """Verify alert rules are properly configured"""
    alerts = [
        "LeagueUpdateMissing",
        "StorageNearlyFull",
        "APIRateLimitExceeded",
        "JobExecutionTooLong"
    ]
    
    prometheus_url = "http://prometheus:9090"
    response = requests.get(f"{prometheus_url}/api/v1/rules")
    
    assert response.status_code == 200
    configured_alerts = [rule['name'] for group in response.json()['data']['groups'] 
                        for rule in group['rules']]
    
    for alert in alerts:
        assert alert in configured_alerts, f"Alert {alert} not configured"
```

### 7. Data Consistency Tests

#### Test: Concurrent Access Handling
```r
# test_data_consistency.R
test_that("Concurrent league updates don't corrupt data", {
  # Create test directory
  test_dir <- tempdir()
  
  # Simulate concurrent writes
  future::plan(future::multisession, workers = 3)
  
  results <- future.apply::future_lapply(c("BL", "BL2", "Liga3"), function(league) {
    # Simulate league update writing results
    result_data <- list(
      league = league,
      timestamp = Sys.time(),
      data = runif(100)
    )
    
    file_path <- file.path(test_dir, paste0("Ergebnis_", league, ".Rds"))
    saveRDS(result_data, file_path)
    
    # Verify write succeeded
    file.exists(file_path)
  })
  
  # All writes should succeed
  expect_true(all(unlist(results)))
  
  # Verify all files are readable and valid
  for (league in c("BL", "BL2", "Liga3")) {
    file_path <- file.path(test_dir, paste0("Ergebnis_", league, ".Rds"))
    data <- readRDS(file_path)
    
    expect_equal(data$league, league)
    expect_s3_class(data$timestamp, "POSIXct")
    expect_length(data$data, 100)
  }
  
  # Cleanup
  unlink(test_dir, recursive = TRUE)
})
```

### 8. Shiny Hybrid Deployment Tests

#### Test: Shiny Deployment Management
```bash
# test_shiny_hybrid.sh
#!/bin/bash

test_shiny_start_stop() {
  # Test start script
  ./scripts/start_shiny_deployment.sh
  
  # Wait for deployment to be ready
  kubectl wait --for=condition=available deployment/shiny-updater \
    -n league-simulator --timeout=60s
  
  # Verify pod is running
  running_pods=$(kubectl get pods -n league-simulator \
    -l app=shiny-updater --field-selector=status.phase=Running \
    --no-headers | wc -l)
  
  if [[ $running_pods -ne 1 ]]; then
    echo "FAIL: Shiny deployment not running"
    return 1
  fi
  
  # Test stop script
  ./scripts/stop_shiny_deployment.sh
  
  # Verify deployment scaled to 0
  replicas=$(kubectl get deployment shiny-updater -n league-simulator \
    -o jsonpath='{.spec.replicas}')
  
  if [[ $replicas -ne 0 ]]; then
    echo "FAIL: Shiny deployment not stopped"
    return 1
  fi
}

test_shiny_update_frequency() {
  # Start deployment
  kubectl scale deployment shiny-updater -n league-simulator --replicas=1
  
  # Monitor update frequency for 15 minutes
  start_time=$(date +%s)
  update_count=0
  last_update=""
  
  while (( $(date +%s) - start_time < 900 )); do
    # Check for new update
    current_update=$(kubectl exec -n league-simulator \
      deployment/shiny-updater -- \
      stat -c %Y /ShinyApp/data/Ergebnis.Rds 2>/dev/null || echo "0")
    
    if [[ "$current_update" != "$last_update" ]] && [[ "$current_update" != "0" ]]; then
      update_count=$((update_count + 1))
      last_update=$current_update
      echo "Update $update_count at $(date)"
    fi
    
    sleep 30
  done
  
  # Expect at least 2 updates in 15 minutes (5-minute interval)
  if [[ $update_count -lt 2 ]]; then
    echo "FAIL: Expected at least 2 updates, got $update_count"
    return 1
  fi
}
```

#### Test: Shiny CronJob Scheduling
```yaml
# test_shiny_cronjobs.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: shiny-test-scripts
  namespace: league-simulator
data:
  test-schedule.sh: |
    #!/bin/bash
    # Verify CronJobs trigger at correct times
    
    # Check if current time is 14:45
    current_hour=$(date +%H)
    current_minute=$(date +%M)
    
    if [[ "$current_hour" == "14" ]] && [[ "$current_minute" == "45" ]]; then
      # Shiny should start
      kubectl get deployment shiny-updater -n league-simulator \
        -o jsonpath='{.spec.replicas}' | grep -q "1" || exit 1
    fi
    
    if [[ "$current_hour" == "23" ]] && [[ "$current_minute" == "35" ]]; then
      # Shiny should stop
      kubectl get deployment shiny-updater -n league-simulator \
        -o jsonpath='{.spec.replicas}' | grep -q "0" || exit 1
    fi
---
apiVersion: batch/v1
kind: Job
metadata:
  name: test-shiny-schedule
  namespace: league-simulator
spec:
  template:
    spec:
      containers:
      - name: test
        image: bitnami/kubectl:latest
        command: ["/scripts/test-schedule.sh"]
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: shiny-test-scripts
          defaultMode: 0755
      restartPolicy: Never
```

### Test Execution Plan

1. **Pre-Migration Tests**
   - Run all unit tests locally
   - Validate YAML syntax
   - Test RUN_ONCE implementation

2. **Migration Tests**
   - Deploy to test cluster
   - Run shadow deployment tests
   - Measure performance metrics

3. **Post-Migration Tests**
   - Monitor job success rates
   - Verify data consistency
   - Test rollback procedure

4. **Continuous Testing**
   - Automated test runs on PR
   - Nightly integration tests
   - Weekly performance benchmarks

### Success Criteria
- All unit tests pass
- Integration tests succeed in test environment
- Performance within 30-minute window
- Rollback completes in <15 minutes
- No data corruption in concurrent tests
- Monitoring alerts configured and firing correctly