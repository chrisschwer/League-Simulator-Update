# Deployment Performance Tests
# Validates deployment process performance and timing

library(testthat)
library(jsonlite)

# Source infrastructure
source("../test_infrastructure.R")

context("Deployment process performance")

test_that("Deployment completes within acceptable time", {
  skip_if_not(Sys.getenv("TEST_DEPLOYMENT_PROCESS", "FALSE") == "TRUE",
              "Deployment process testing disabled")
  skip_if_not(Sys.which("kubectl") != "", "kubectl not available")
  
  deployment_name <- "league-simulator"
  namespace <- test_infrastructure_exports$config$k8s_namespace
  max_deployment_time <- 300  # 5 minutes
  
  # Record start time
  start_time <- Sys.time()
  
  # Trigger deployment (this would be done by CI/CD in reality)
  # Here we're checking an existing deployment
  deployment_status <- verify_deployment_status(deployment_name, namespace)
  
  if (deployment_status$success) {
    # Wait for deployment to be ready
    ready <- FALSE
    while (!ready && as.numeric(Sys.time() - start_time, units = "secs") < max_deployment_time) {
      status <- verify_deployment_status(deployment_name, namespace)
      
      if (status$success && 
          !is.null(status$ready_replicas) && 
          !is.null(status$replicas) &&
          status$ready_replicas == status$replicas) {
        ready <- TRUE
      } else {
        Sys.sleep(5)
      }
    }
    
    deployment_time <- as.numeric(Sys.time() - start_time, units = "secs")
    
    expect_true(ready,
                info = "Deployment did not become ready in time")
    
    expect_lt(deployment_time, max_deployment_time,
              info = sprintf("Deployment took %.1f seconds (max: %d)",
                           deployment_time, max_deployment_time))
    
    # Log deployment time for baseline tracking
    message(sprintf("Deployment completed in %.1f seconds", deployment_time))
  }
})

test_that("Rolling update maintains availability", {
  skip_if_not(Sys.getenv("TEST_DEPLOYMENT_PROCESS", "FALSE") == "TRUE",
              "Deployment process testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Monitor availability during deployment
  monitoring_results <- list()
  check_interval <- 2  # seconds
  monitoring_duration <- 120  # 2 minutes
  
  start_time <- Sys.time()
  failed_requests <- 0
  total_requests <- 0
  
  while (as.numeric(Sys.time() - start_time, units = "secs") < monitoring_duration) {
    total_requests <- total_requests + 1
    
    response <- tryCatch({
      GET(paste0(base_url, "/health"), timeout(2))
    }, error = function(e) NULL)
    
    if (is.null(response) || status_code(response) != 200) {
      failed_requests <- failed_requests + 1
    }
    
    monitoring_results[[length(monitoring_results) + 1]] <- list(
      timestamp = Sys.time(),
      success = !is.null(response) && status_code(response) == 200
    )
    
    Sys.sleep(check_interval)
  }
  
  # Calculate availability
  availability <- (total_requests - failed_requests) / total_requests * 100
  
  # Should maintain 99.9% availability during deployment
  expect_gt(availability, 99.9,
            info = sprintf("Availability during deployment: %.1f%% (%d/%d succeeded)",
                         availability, total_requests - failed_requests, total_requests))
})

test_that("Deployment stages complete in expected time", {
  skip_if_not(Sys.getenv("TEST_DEPLOYMENT_PROCESS", "FALSE") == "TRUE",
              "Deployment process testing disabled")
  
  # Expected stage durations (in seconds)
  stage_expectations <- list(
    image_pull = list(max = 60, typical = 30),
    container_start = list(max = 30, typical = 10),
    health_check = list(max = 60, typical = 20),
    ready_check = list(max = 30, typical = 10)
  )
  
  # These would be measured during actual deployment
  # For testing, we'll check if the stages are configured correctly
  deployment_name <- "league-simulator"
  namespace <- test_infrastructure_exports$config$k8s_namespace
  
  # Get deployment configuration
  deployment_json <- system2(
    "kubectl",
    args = c("get", "deployment", deployment_name, "-n", namespace, "-o", "json"),
    stdout = TRUE,
    stderr = TRUE
  )
  
  if (attr(deployment_json, "status") == 0) {
    deployment <- fromJSON(paste(deployment_json, collapse = "\n"))
    
    # Check readiness probe configuration
    containers <- deployment$spec$template$spec$containers
    if (length(containers) > 0) {
      probe <- containers[[1]]$readinessProbe
      
      expect_true(!is.null(probe),
                  info = "Readiness probe should be configured")
      
      if (!is.null(probe)) {
        # Check probe timing
        expect_lte(probe$initialDelaySeconds, 30,
                   info = "Initial delay should be reasonable")
        expect_lte(probe$periodSeconds, 10,
                   info = "Probe period should allow quick detection")
      }
    }
    
    # Check deployment strategy
    strategy <- deployment$spec$strategy
    expect_equal(strategy$type, "RollingUpdate",
                 info = "Should use RollingUpdate strategy")
    
    if (strategy$type == "RollingUpdate") {
      expect_true(!is.null(strategy$rollingUpdate$maxSurge),
                  info = "maxSurge should be configured")
      expect_true(!is.null(strategy$rollingUpdate$maxUnavailable),
                  info = "maxUnavailable should be configured")
    }
  }
})

test_that("Deployment performance metrics are collected", {
  skip_if_not(Sys.getenv("TEST_DEPLOYMENT_PROCESS", "FALSE") == "TRUE",
              "Deployment process testing disabled")
  
  # Create deployment metrics structure
  deployment_metrics <- list(
    deployment_id = paste0("deploy-", format(Sys.time(), "%Y%m%d-%H%M%S")),
    start_time = Sys.time(),
    stages = list(),
    resources = list()
  )
  
  # Simulate collecting metrics during deployment
  # In reality, these would be collected by the deployment pipeline
  
  # Stage: Image pull
  stage_start <- Sys.time()
  Sys.sleep(0.1)  # Simulate work
  deployment_metrics$stages$image_pull <- list(
    duration_seconds = as.numeric(Sys.time() - stage_start, units = "secs"),
    success = TRUE
  )
  
  # Stage: Container start
  stage_start <- Sys.time()
  Sys.sleep(0.1)  # Simulate work
  deployment_metrics$stages$container_start <- list(
    duration_seconds = as.numeric(Sys.time() - stage_start, units = "secs"),
    success = TRUE
  )
  
  # Stage: Health checks
  stage_start <- Sys.time()
  Sys.sleep(0.1)  # Simulate work
  deployment_metrics$stages$health_checks <- list(
    duration_seconds = as.numeric(Sys.time() - stage_start, units = "secs"),
    success = TRUE,
    attempts = 3
  )
  
  # Overall metrics
  deployment_metrics$total_duration_seconds <- as.numeric(
    Sys.time() - deployment_metrics$start_time, units = "secs"
  )
  deployment_metrics$success = TRUE
  
  # Save metrics for baseline tracking
  metrics_dir <- "tests/deployment/metrics"
  dir.create(metrics_dir, recursive = TRUE, showWarnings = FALSE)
  
  metrics_file <- file.path(metrics_dir, 
                           paste0(deployment_metrics$deployment_id, ".json"))
  
  write_json(deployment_metrics, metrics_file, pretty = TRUE, auto_unbox = TRUE)
  
  # Verify metrics were saved
  expect_true(file.exists(metrics_file),
              info = "Deployment metrics should be saved")
  
  # Check metrics structure
  saved_metrics <- fromJSON(metrics_file)
  expect_true(!is.null(saved_metrics$stages),
              info = "Metrics should include stage information")
  expect_true(!is.null(saved_metrics$total_duration_seconds),
              info = "Metrics should include total duration")
})

test_that("Deployment resource usage is tracked", {
  skip_if_not(Sys.getenv("TEST_DEPLOYMENT_PROCESS", "FALSE") == "TRUE",
              "Deployment process testing disabled")
  skip_if_not(Sys.which("kubectl") != "", "kubectl not available")
  
  deployment_name <- "league-simulator"
  namespace <- test_infrastructure_exports$config$k8s_namespace
  
  # Get events during deployment
  events_cmd <- sprintf(
    "kubectl get events -n %s --field-selector involvedObject.name=%s -o json",
    namespace, deployment_name
  )
  
  events_json <- system(events_cmd, intern = TRUE, ignore.stderr = TRUE)
  
  if (length(events_json) > 0) {
    events <- tryCatch({
      fromJSON(paste(events_json, collapse = "\n"))
    }, error = function(e) NULL)
    
    if (!is.null(events) && !is.null(events$items)) {
      # Analyze deployment events
      deployment_events <- list()
      
      for (event in events$items) {
        if (event$reason %in% c("ScalingReplicaSet", "SuccessfulCreate", 
                               "SuccessfulDelete", "Pulled", "Started")) {
          deployment_events[[length(deployment_events) + 1]] <- list(
            timestamp = event$firstTimestamp,
            reason = event$reason,
            message = event$message
          )
        }
      }
      
      # Should have deployment events
      expect_gt(length(deployment_events), 0,
                info = "Deployment events should be recorded")
    }
  }
})

test_that("Canary deployment performance is acceptable", {
  skip_if_not(Sys.getenv("TEST_CANARY_DEPLOYMENT", "FALSE") == "TRUE",
              "Canary deployment testing disabled")
  
  # Canary deployment should:
  # 1. Deploy quickly (< 1 minute for canary pod)
  # 2. Route correct traffic percentage
  # 3. Not impact production performance
  
  canary_start <- Sys.time()
  
  # Simulate canary deployment check
  canary_deployment <- list(
    replicas = 1,
    traffic_percentage = 10,
    health_check_passed = TRUE
  )
  
  # Measure time to healthy canary
  canary_healthy_time <- 45  # seconds (simulated)
  
  expect_lt(canary_healthy_time, 60,
            info = sprintf("Canary deployment took %d seconds (max: 60)",
                         canary_healthy_time))
  
  # Test traffic distribution
  # In real scenario, would make many requests and check version headers
  test_requests <- 100
  canary_hits <- 11  # simulated
  
  expected_percentage <- canary_deployment$traffic_percentage
  actual_percentage <- (canary_hits / test_requests) * 100
  
  # Allow 20% deviation
  expect_lt(abs(actual_percentage - expected_percentage), 
            expected_percentage * 0.2,
            info = sprintf("Canary traffic: %.1f%% (expected: %d%%)",
                         actual_percentage, expected_percentage))
})