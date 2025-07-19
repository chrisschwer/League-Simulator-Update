# Post-Deployment Performance Validation Tests
# Ensures deployed application meets performance SLAs

library(testthat)
library(httr)
library(microbenchmark)

# Source infrastructure and baseline helpers
source("../test_infrastructure.R")
source("../../testthat/helper-performance-baseline.R")

context("Post-deployment performance validation")

test_that("API response times meet SLA after deployment", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test various endpoints
  endpoints <- list(
    list(path = "/api/status", sla_ms = 100, percentile_95_ms = 200),
    list(path = "/health", sla_ms = 50, percentile_95_ms = 100),
    list(path = "/api/teams", sla_ms = 200, percentile_95_ms = 500)
  )
  
  for (endpoint in endpoints) {
    # Measure response times for 100 requests
    response_times <- numeric(100)
    
    for (i in 1:100) {
      start_time <- Sys.time()
      response <- tryCatch({
        GET(paste0(base_url, endpoint$path), timeout(5))
      }, error = function(e) NULL)
      end_time <- Sys.time()
      
      if (!is.null(response) && status_code(response) == 200) {
        response_times[i] <- as.numeric(end_time - start_time, units = "secs") * 1000
      } else {
        response_times[i] <- NA
      }
      
      # Small delay between requests
      Sys.sleep(0.05)
    }
    
    # Remove failed requests
    valid_times <- response_times[!is.na(response_times)]
    
    # Check success rate
    success_rate <- length(valid_times) / length(response_times)
    expect_gt(success_rate, 0.99,
              info = sprintf("%s: Success rate %.1f%% (expected >99%%)",
                           endpoint$path, success_rate * 100))
    
    # Check median response time
    median_time <- median(valid_times)
    expect_lt(median_time, endpoint$sla_ms,
              info = sprintf("%s: Median response time %.1fms (SLA: %dms)",
                           endpoint$path, median_time, endpoint$sla_ms))
    
    # Check 95th percentile
    p95_time <- quantile(valid_times, 0.95)
    expect_lt(p95_time, endpoint$percentile_95_ms,
              info = sprintf("%s: 95th percentile %.1fms (SLA: %dms)",
                           endpoint$path, p95_time, endpoint$percentile_95_ms))
  }
})

test_that("Simulation performance matches baseline after deployment", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  baseline <- load_baseline()
  
  # Test small simulation
  sim_request <- list(
    league = "Bundesliga",
    iterations = 100
  )
  
  # Run 5 test simulations
  sim_times <- numeric(5)
  
  for (i in 1:5) {
    start_time <- Sys.time()
    response <- POST(
      paste0(base_url, "/api/simulate"),
      body = sim_request,
      encode = "json",
      timeout(30)
    )
    end_time <- Sys.time()
    
    expect_equal(status_code(response), 200,
                 info = "Simulation endpoint should return 200")
    
    sim_times[i] <- as.numeric(end_time - start_time, units = "secs") * 1000
  }
  
  # Compare to baseline (with network overhead allowance)
  median_time <- median(sim_times)
  baseline_time <- baseline$iteration_scaling$`100`
  network_overhead_allowance <- 50  # 50ms for network
  
  expected_time <- baseline_time + network_overhead_allowance
  
  expect_lt(median_time, expected_time * 1.2,
            info = sprintf("Deployed simulation time %.1fms (baseline+network: %.1fms)",
                         median_time, expected_time))
})

test_that("Memory usage is within limits", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  skip_if_not(Sys.which("kubectl") != "", "kubectl not available")
  
  deployment_name <- "league-simulator"
  namespace <- test_infrastructure_exports$config$k8s_namespace
  
  # Get pod memory usage
  pod_metrics <- system2(
    "kubectl",
    args = c("top", "pod", "-l", paste0("app=", deployment_name),
             "-n", namespace, "--no-headers"),
    stdout = TRUE,
    stderr = TRUE
  )
  
  if (attr(pod_metrics, "status") == 0 && length(pod_metrics) > 0) {
    # Parse memory values (format: "pod-name CPU memory")
    for (line in pod_metrics) {
      parts <- strsplit(trimws(line), "\\s+")[[1]]
      if (length(parts) >= 3) {
        memory_str <- parts[3]
        
        # Convert to MB (handles Mi, M suffixes)
        memory_mb <- as.numeric(gsub("[^0-9]", "", memory_str))
        if (grepl("Gi", memory_str)) memory_mb <- memory_mb * 1024
        
        expect_lt(memory_mb, 1024,
                  info = sprintf("Pod %s using %.0fMB (limit: 1024MB)",
                               parts[1], memory_mb))
      }
    }
  }
})

test_that("Concurrent request handling performs adequately", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test concurrent requests using parallel processing
  library(parallel)
  
  # Function to make a request and measure time
  make_request <- function(i) {
    start_time <- Sys.time()
    response <- tryCatch({
      GET(paste0(base_url, "/api/status"), timeout(5))
    }, error = function(e) NULL)
    end_time <- Sys.time()
    
    list(
      success = !is.null(response) && status_code(response) == 200,
      time_ms = as.numeric(end_time - start_time, units = "secs") * 1000
    )
  }
  
  # Run 20 concurrent requests
  cl <- makeCluster(4)  # Use 4 cores
  clusterEvalQ(cl, library(httr))
  clusterExport(cl, c("base_url"))
  
  results <- parLapply(cl, 1:20, make_request)
  stopCluster(cl)
  
  # Analyze results
  success_count <- sum(sapply(results, function(x) x$success))
  response_times <- sapply(results, function(x) x$time_ms)
  
  # All requests should succeed
  expect_equal(success_count, 20,
               info = sprintf("Concurrent requests: %d/20 succeeded", success_count))
  
  # Response times should not degrade significantly under load
  expect_lt(max(response_times), 500,
            info = sprintf("Max response time under load: %.1fms", max(response_times)))
})

test_that("Performance degradation is detected", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  baseline <- load_baseline()
  
  # Monitor performance over time
  monitoring_duration <- 60  # seconds
  check_interval <- 5  # seconds
  
  start_monitoring <- Sys.time()
  performance_samples <- list()
  
  while (as.numeric(Sys.time() - start_monitoring, units = "secs") < monitoring_duration) {
    # Make test request
    request_start <- Sys.time()
    response <- GET(paste0(base_url, "/api/status"))
    request_end <- Sys.time()
    
    if (status_code(response) == 200) {
      response_time <- as.numeric(request_end - request_start, units = "secs") * 1000
      
      performance_samples[[length(performance_samples) + 1]] <- list(
        timestamp = Sys.time(),
        response_time_ms = response_time
      )
    }
    
    Sys.sleep(check_interval)
  }
  
  # Check for performance degradation
  if (length(performance_samples) > 5) {
    response_times <- sapply(performance_samples, function(x) x$response_time_ms)
    
    # Calculate trend (should be stable or improving)
    time_indices <- 1:length(response_times)
    trend_model <- lm(response_times ~ time_indices)
    
    # Slope should not be significantly positive (indicating degradation)
    slope <- coef(trend_model)[2]
    
    # Allow up to 1ms increase per sample
    expect_lt(slope, 1,
              info = sprintf("Performance trend: %.2fms increase per sample", slope))
  }
})

test_that("Resource utilization stays within expected bounds", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  skip_if_not(Sys.which("kubectl") != "", "kubectl not available")
  
  deployment_name <- "league-simulator"
  namespace <- test_infrastructure_exports$config$k8s_namespace
  
  # Get resource metrics
  metrics_cmd <- sprintf(
    'kubectl top pod -l app=%s -n %s --no-headers | awk \'{print $2 " " $3}\'',
    deployment_name, namespace
  )
  
  metrics_output <- system(metrics_cmd, intern = TRUE)
  
  if (length(metrics_output) > 0) {
    for (line in metrics_output) {
      parts <- strsplit(trimws(line), " ")[[1]]
      if (length(parts) == 2) {
        cpu_str <- parts[1]
        mem_str <- parts[2]
        
        # Parse CPU (in millicores)
        cpu_millicores <- as.numeric(gsub("m", "", cpu_str))
        
        # CPU should be under 80% of limit (assuming 1000m limit)
        expect_lt(cpu_millicores, 800,
                  info = sprintf("CPU usage: %dm (limit: 800m)", cpu_millicores))
      }
    }
  }
})