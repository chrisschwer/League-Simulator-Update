# Health Check Endpoint Tests
# Validates health and readiness endpoints before deployment

library(testthat)
library(httr)
library(jsonlite)

# Source the test infrastructure
source("../test_infrastructure.R")

context("Health check endpoints")

test_that("Health check endpoint responds correctly", {
  skip_if_not(Sys.getenv("TEST_HEALTH_ENDPOINTS", "FALSE") == "TRUE",
              "Health endpoint testing disabled")
  
  base_url <- test_infrastructure_exports$config$staging_url
  response <- GET(paste0(base_url, "/health"))
  
  # Check status code
  expect_equal(status_code(response), 200,
               info = "Health endpoint should return 200 OK")
  
  # Parse response
  health_data <- content(response, as = "parsed")
  
  # Validate response structure
  expect_true("status" %in% names(health_data),
              info = "Health response missing 'status' field")
  
  expect_equal(health_data$status, "healthy",
               info = "Service reporting unhealthy status")
  
  # Check for subsystem health
  expect_true("checks" %in% names(health_data),
              info = "Health response missing 'checks' field")
  
  # Validate subsystem checks
  expected_checks <- c("database", "api", "filesystem")
  for (check in expected_checks) {
    if (check %in% names(health_data$checks)) {
      expect_true(health_data$checks[[check]]$healthy,
                  info = sprintf("Subsystem %s is unhealthy", check))
    }
  }
  
  # Check response time
  expect_true("response_time_ms" %in% names(health_data),
              info = "Health response missing response time")
  
  if ("response_time_ms" %in% names(health_data)) {
    expect_true(health_data$response_time_ms < 1000,
                info = "Health check response time exceeds 1 second")
  }
})

test_that("Readiness check validates all services", {
  skip_if_not(Sys.getenv("TEST_HEALTH_ENDPOINTS", "FALSE") == "TRUE",
              "Health endpoint testing disabled")
  
  base_url <- test_infrastructure_exports$config$staging_url
  response <- GET(paste0(base_url, "/ready"))
  
  # Check status code
  expect_equal(status_code(response), 200,
               info = "Ready endpoint should return 200 when ready")
  
  # Parse response
  ready_data <- content(response, as = "parsed")
  
  # Validate response structure
  expect_true("ready" %in% names(ready_data),
              info = "Ready response missing 'ready' field")
  
  expect_true(ready_data$ready,
              info = "Service reporting not ready")
  
  # Check service statuses
  expect_true("services" %in% names(ready_data),
              info = "Ready response missing 'services' field")
  
  if ("services" %in% names(ready_data)) {
    for (service_name in names(ready_data$services)) {
      service <- ready_data$services[[service_name]]
      expect_equal(service$status, "ready",
                   info = sprintf("Service %s is not ready", service_name))
    }
  }
})

test_that("Health check endpoint handles errors gracefully", {
  skip_if_not(Sys.getenv("TEST_HEALTH_ENDPOINTS", "FALSE") == "TRUE",
              "Health endpoint testing disabled")
  
  # Test with invalid endpoint
  base_url <- test_infrastructure_exports$config$staging_url
  response <- GET(paste0(base_url, "/health/invalid"))
  
  # Should return 404
  expect_equal(status_code(response), 404,
               info = "Invalid health endpoint should return 404")
})

test_that("Liveness probe works correctly", {
  skip_if_not(Sys.getenv("TEST_HEALTH_ENDPOINTS", "FALSE") == "TRUE",
              "Health endpoint testing disabled")
  
  base_url <- test_infrastructure_exports$config$staging_url
  
  # Liveness should be a simple, fast check
  start_time <- Sys.time()
  response <- GET(paste0(base_url, "/alive"))
  end_time <- Sys.time()
  
  # Check response
  expect_equal(status_code(response), 200,
               info = "Liveness endpoint should return 200")
  
  # Check response time (should be very fast)
  response_time <- as.numeric(end_time - start_time, units = "secs")
  expect_true(response_time < 0.1,
              info = sprintf("Liveness check too slow: %.3f seconds", response_time))
})

test_that("Health checks include version information", {
  skip_if_not(Sys.getenv("TEST_HEALTH_ENDPOINTS", "FALSE") == "TRUE",
              "Health endpoint testing disabled")
  
  base_url <- test_infrastructure_exports$config$staging_url
  response <- GET(paste0(base_url, "/health"))
  
  health_data <- content(response, as = "parsed")
  
  # Check for version info
  expect_true("version" %in% names(health_data),
              info = "Health response missing version information")
  
  if ("version" %in% names(health_data)) {
    expect_true("app" %in% names(health_data$version),
                info = "Version info missing app version")
    expect_true("api" %in% names(health_data$version),
                info = "Version info missing API version")
  }
})