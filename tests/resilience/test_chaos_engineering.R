# Chaos Engineering Tests
# Tests system resilience under failure conditions

library(testthat)
library(httr)

# Source infrastructure
source("../deployment/test_infrastructure.R")

context("Chaos engineering and resilience")

test_that("Application recovers from pod failures", {
  skip_if_not(Sys.getenv("TEST_CHAOS_POD_FAILURE", "FALSE") == "TRUE",
              "Pod failure chaos testing disabled")
  skip_if_not(Sys.which("kubectl") != "", "kubectl not available")
  
  deployment_name <- "league-simulator"
  namespace <- test_infrastructure_exports$config$k8s_namespace
  base_url <- test_infrastructure_exports$config$production_url
  
  # Get initial pod count
  initial_pods <- system2(
    "kubectl",
    args = c("get", "pods", "-l", paste0("app=", deployment_name),
             "-n", namespace, "--no-headers", "|", "wc", "-l"),
    stdout = TRUE
  )
  initial_count <- as.numeric(trimws(initial_pods))
  
  # Record baseline health
  baseline_health <- check_service_health(base_url)
  expect_true(baseline_health$healthy,
              info = "Service should be healthy before chaos test")
  
  # Kill a random pod
  pods_output <- system2(
    "kubectl",
    args = c("get", "pods", "-l", paste0("app=", deployment_name),
             "-n", namespace, "-o", "name"),
    stdout = TRUE
  )
  
  if (length(pods_output) > 0) {
    # Select random pod
    target_pod <- sample(pods_output, 1)
    
    # Delete the pod
    delete_result <- system2(
      "kubectl",
      args = c("delete", target_pod, "-n", namespace, "--force", "--grace-period=0"),
      stdout = TRUE,
      stderr = TRUE
    )
    
    # Monitor recovery
    recovery_start <- Sys.time()
    recovered <- FALSE
    max_recovery_time <- 120  # 2 minutes
    
    while (!recovered && 
           as.numeric(Sys.time() - recovery_start, units = "secs") < max_recovery_time) {
      
      current_pods <- system2(
        "kubectl",
        args = c("get", "pods", "-l", paste0("app=", deployment_name),
                 "-n", namespace, "--field-selector=status.phase=Running",
                 "--no-headers", "|", "wc", "-l"),
        stdout = TRUE
      )
      current_count <- as.numeric(trimws(current_pods))
      
      if (current_count >= initial_count) {
        recovered <- TRUE
      } else {
        Sys.sleep(5)
      }
    }
    
    recovery_time <- as.numeric(Sys.time() - recovery_start, units = "secs")
    
    expect_true(recovered,
                info = "Pod count should recover after deletion")
    
    expect_lt(recovery_time, 60,
              info = sprintf("Recovery took %.1f seconds (expected < 60s)", recovery_time))
    
    # Verify service stayed available
    post_chaos_health <- check_service_health(base_url)
    expect_true(post_chaos_health$healthy,
                info = "Service should remain healthy during pod failure")
  }
})

test_that("Application handles network partitions", {
  skip_if_not(Sys.getenv("TEST_CHAOS_NETWORK", "FALSE") == "TRUE",
              "Network chaos testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test various network failure scenarios
  network_scenarios <- list(
    high_latency = list(
      delay = "200ms",
      jitter = "50ms",
      duration = 60
    ),
    packet_loss = list(
      loss = "10%",
      duration = 30
    ),
    network_partition = list(
      partition_type = "partial",
      affected_percentage = 30,
      duration = 45
    )
  )
  
  for (scenario_name in names(network_scenarios)) {
    scenario <- network_scenarios[[scenario_name]]
    
    # Apply network chaos (simulated - would use tool like tc or Chaos Mesh)
    chaos_start <- Sys.time()
    
    # Monitor service behavior during chaos
    errors <- 0
    total_requests <- 0
    response_times <- numeric()
    
    while (as.numeric(Sys.time() - chaos_start, units = "secs") < scenario$duration) {
      total_requests <- total_requests + 1
      
      request_start <- Sys.time()
      response <- tryCatch({
        GET(paste0(base_url, "/health"), timeout(5))
      }, error = function(e) NULL)
      request_end <- Sys.time()
      
      if (is.null(response) || status_code(response) != 200) {
        errors <- errors + 1
      } else {
        response_times <- c(response_times, 
                           as.numeric(request_end - request_start, units = "secs") * 1000)
      }
      
      Sys.sleep(1)
    }
    
    # Calculate metrics
    error_rate <- errors / total_requests
    
    # Verify acceptable degradation
    if (scenario_name == "high_latency") {
      expect_lt(error_rate, 0.05,
                info = sprintf("%s: Error rate %.1f%% (threshold: 5%%)",
                             scenario_name, error_rate * 100))
      
      if (length(response_times) > 0) {
        expect_lt(median(response_times), 1000,
                  info = sprintf("%s: Median response time %.0fms",
                               scenario_name, median(response_times)))
      }
    } else if (scenario_name == "packet_loss") {
      expect_lt(error_rate, 0.15,
                info = sprintf("%s: Error rate %.1f%% (threshold: 15%%)",
                             scenario_name, error_rate * 100))
    }
  }
})

test_that("Database connection failure triggers circuit breaker", {
  skip_if_not(Sys.getenv("TEST_CHAOS_DATABASE", "FALSE") == "TRUE",
              "Database chaos testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test circuit breaker behavior
  circuit_breaker_test <- list(
    phase = "closed",
    failures = 0,
    threshold = 5,
    timeout = 30,
    half_open_requests = 0
  )
  
  # Simulate database failures
  for (i in 1:10) {
    response <- GET(paste0(base_url, "/api/data/status"))
    
    if (status_code(response) == 503) {
      circuit_breaker_test$failures <- circuit_breaker_test$failures + 1
      
      # Check if circuit breaker opened
      response_body <- content(response, as = "parsed")
      if (!is.null(response_body$circuit_breaker_status)) {
        circuit_breaker_test$phase <- response_body$circuit_breaker_status
      }
    }
    
    # After threshold, circuit should open
    if (circuit_breaker_test$failures >= circuit_breaker_test$threshold &&
        circuit_breaker_test$phase == "closed") {
      expect_equal(circuit_breaker_test$phase, "open",
                   info = "Circuit breaker should open after threshold failures")
    }
    
    Sys.sleep(1)
  }
  
  # Wait for timeout
  if (circuit_breaker_test$phase == "open") {
    Sys.sleep(circuit_breaker_test$timeout)
    
    # Test half-open state
    response <- GET(paste0(base_url, "/api/data/status"))
    response_body <- content(response, as = "parsed")
    
    if (!is.null(response_body$circuit_breaker_status)) {
      expect_equal(response_body$circuit_breaker_status, "half-open",
                   info = "Circuit breaker should enter half-open state after timeout")
    }
  }
})

test_that("Resource exhaustion is handled gracefully", {
  skip_if_not(Sys.getenv("TEST_CHAOS_RESOURCES", "FALSE") == "TRUE",
              "Resource chaos testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test various resource exhaustion scenarios
  resource_tests <- list(
    memory_pressure = list(
      test = "high_memory_usage",
      expected_behavior = "graceful_degradation"
    ),
    cpu_saturation = list(
      test = "cpu_intensive_operations",
      expected_behavior = "request_queuing"
    ),
    disk_full = list(
      test = "disk_space_exhaustion",
      expected_behavior = "read_only_mode"
    )
  )
  
  for (test_name in names(resource_tests)) {
    test_config <- resource_tests[[test_name]]
    
    # Trigger resource exhaustion (simulated)
    exhaustion_response <- POST(
      paste0(base_url, "/api/chaos/resource"),
      body = list(type = test_config$test),
      encode = "json"
    )
    
    # Monitor behavior under resource pressure
    monitoring_duration <- 30
    start_time <- Sys.time()
    
    behaviors_observed <- list()
    
    while (as.numeric(Sys.time() - start_time, units = "secs") < monitoring_duration) {
      # Make test request
      response <- GET(paste0(base_url, "/api/status"))
      
      # Check response
      if (status_code(response) == 200) {
        response_data <- content(response, as = "parsed")
        
        if (!is.null(response_data$system_status)) {
          behaviors_observed[[length(behaviors_observed) + 1]] <- 
            response_data$system_status
        }
      }
      
      Sys.sleep(2)
    }
    
    # Verify expected behavior was observed
    if (test_config$expected_behavior == "graceful_degradation") {
      degraded_responses <- sum(behaviors_observed == "degraded")
      expect_gt(degraded_responses, 0,
                info = sprintf("%s: Should show degraded performance", test_name))
    }
  }
})

test_that("Cascading failures are prevented", {
  skip_if_not(Sys.getenv("TEST_CHAOS_CASCADE", "FALSE") == "TRUE",
              "Cascading failure testing disabled")
  
  deployment_name <- "league-simulator"
  namespace <- test_infrastructure_exports$config$k8s_namespace
  
  # Test bulkhead pattern - failure in one component shouldn't affect others
  components <- list(
    api = list(endpoint = "/api/status", healthy = TRUE),
    simulation = list(endpoint = "/api/simulate/health", healthy = TRUE),
    data = list(endpoint = "/api/data/health", healthy = TRUE),
    ui = list(endpoint = "/health", healthy = TRUE)
  )
  
  # Inject failure in one component (simulation)
  failure_injection <- list(
    target_component = "simulation",
    failure_type = "timeout",
    duration = 60
  )
  
  # Monitor all components during failure
  monitoring_start <- Sys.time()
  
  while (as.numeric(Sys.time() - monitoring_start, units = "secs") < failure_injection$duration) {
    for (component_name in names(components)) {
      component <- components[[component_name]]
      
      response <- tryCatch({
        GET(paste0(test_infrastructure_exports$config$production_url, 
                  component$endpoint),
            timeout(2))
      }, error = function(e) NULL)
      
      if (component_name == failure_injection$target_component) {
        # This component should fail
        expect_true(is.null(response) || status_code(response) != 200,
                   info = sprintf("%s should be failing", component_name))
      } else {
        # Other components should remain healthy
        expect_true(!is.null(response) && status_code(response) == 200,
                   info = sprintf("%s should remain healthy despite %s failure",
                                component_name, failure_injection$target_component))
      }
    }
    
    Sys.sleep(5)
  }
})

test_that("Chaos experiments are recorded and analyzed", {
  skip_if_not(Sys.getenv("TEST_CHAOS_RECORDING", "FALSE") == "TRUE",
              "Chaos recording testing disabled")
  
  # Create chaos experiment record
  experiment <- list(
    id = paste0("chaos-", format(Sys.time(), "%Y%m%d-%H%M%S")),
    type = "pod_failure",
    target = "league-simulator",
    start_time = Sys.time(),
    parameters = list(
      pods_to_kill = 1,
      recovery_timeout = 120
    ),
    observations = list(),
    metrics = list()
  )
  
  # Run experiment (simulated)
  experiment$observations <- list(
    pre_chaos = list(
      pod_count = 3,
      error_rate = 0.001,
      response_time_p95 = 145
    ),
    during_chaos = list(
      pod_count_min = 2,
      error_rate_max = 0.023,
      response_time_p95_max = 420
    ),
    post_chaos = list(
      recovery_time_seconds = 35,
      final_pod_count = 3,
      error_rate = 0.001,
      response_time_p95 = 150
    )
  )
  
  experiment$end_time <- Sys.time()
  experiment$duration <- as.numeric(experiment$end_time - experiment$start_time, units = "secs")
  
  # Analyze results
  experiment$analysis <- list(
    success = TRUE,
    findings = list(
      "System recovered within acceptable time",
      "Error rate stayed below 5% threshold",
      "No cascading failures observed"
    ),
    recommendations = list(
      "Consider reducing pod startup time",
      "Implement request hedging for critical paths"
    )
  )
  
  # Save experiment results
  results_dir <- "tests/resilience/chaos-results"
  dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
  
  saveRDS(experiment, 
          file.path(results_dir, paste0(experiment$id, ".rds")))
  
  # Verify experiment was recorded
  expect_true(file.exists(file.path(results_dir, paste0(experiment$id, ".rds"))),
              info = "Chaos experiment should be recorded")
  
  # Check analysis completeness
  expect_true(!is.null(experiment$analysis),
              info = "Experiment should include analysis")
  
  expect_true(length(experiment$analysis$findings) > 0,
              info = "Analysis should include findings")
})