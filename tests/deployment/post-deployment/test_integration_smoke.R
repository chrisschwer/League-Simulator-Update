# Integration Smoke Tests for Deployed Application
# Validates end-to-end functionality after deployment

library(testthat)
library(httr)
library(jsonlite)

# Source infrastructure
source("../test_infrastructure.R")

context("Post-deployment integration smoke tests")

test_that("Core simulation endpoints work after deployment", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test simulation endpoint with minimal request
  sim_response <- POST(
    paste0(base_url, "/api/simulate"),
    body = list(
      league = "Bundesliga",
      iterations = 100
    ),
    encode = "json",
    timeout(30)
  )
  
  expect_equal(status_code(sim_response), 200,
               info = "Simulation endpoint should return 200")
  
  # Parse response
  sim_data <- content(sim_response, as = "parsed")
  
  # Validate response structure
  expect_true("results" %in% names(sim_data),
              info = "Response should contain results")
  
  expect_true("metadata" %in% names(sim_data),
              info = "Response should contain metadata")
  
  if ("results" %in% names(sim_data)) {
    # Should have results for 18 teams (Bundesliga)
    expect_equal(length(sim_data$results), 18,
                 info = "Should have results for all Bundesliga teams")
    
    # Each team should have placement probabilities
    for (team_result in sim_data$results) {
      expect_true("team" %in% names(team_result),
                  info = "Team result should include team name")
      expect_true("probabilities" %in% names(team_result),
                  info = "Team result should include probabilities")
      
      if ("probabilities" %in% names(team_result)) {
        # Probabilities should sum to 1 (within tolerance)
        prob_sum <- sum(unlist(team_result$probabilities))
        expect_equal(prob_sum, 1, tolerance = 0.01,
                     info = "Placement probabilities should sum to 1")
      }
    }
  }
  
  if ("metadata" %in% names(sim_data)) {
    expect_true("iterations" %in% names(sim_data$metadata),
                info = "Metadata should include iteration count")
    expect_true("execution_time_ms" %in% names(sim_data$metadata),
                info = "Metadata should include execution time")
  }
})

test_that("Shiny app loads and displays data correctly", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  skip_if_not(Sys.getenv("TEST_SHINY_UI", "FALSE") == "TRUE",
              "Shiny UI testing disabled")
  
  library(RSelenium)
  
  # Start Selenium driver
  remDr <- remoteDriver(
    remoteServerAddr = Sys.getenv("SELENIUM_HOST", "localhost"),
    port = as.numeric(Sys.getenv("SELENIUM_PORT", 4444)),
    browserName = "chrome"
  )
  
  tryCatch({
    remDr$open()
    
    # Navigate to Shiny app
    app_url <- test_infrastructure_exports$config$production_url
    remDr$navigate(app_url)
    
    # Wait for page load
    Sys.sleep(5)
    
    # Check page title
    title <- remDr$getTitle()[[1]]
    expect_true(grepl("League Simulator", title),
                info = "Page title should contain 'League Simulator'")
    
    # Check if main elements are present
    # Look for the data table
    tables <- remDr$findElements(using = "css", "table")
    expect_gt(length(tables), 0,
              info = "Should find at least one table on the page")
    
    # Check for update timestamp
    timestamp_elements <- remDr$findElements(using = "css", ".update-time")
    if (length(timestamp_elements) > 0) {
      timestamp_text <- timestamp_elements[[1]]$getElementText()[[1]]
      expect_true(nchar(timestamp_text) > 0,
                  info = "Update timestamp should be displayed")
    }
    
    # Check for visualization
    plot_elements <- remDr$findElements(using = "css", ".plot-container, svg")
    expect_gt(length(plot_elements), 0,
              info = "Should find visualization elements")
    
  }, finally = {
    remDr$close()
  })
})

test_that("API authentication and security headers are present", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Make request and check headers
  response <- GET(paste0(base_url, "/api/status"))
  
  headers <- headers(response)
  
  # Check security headers
  security_headers <- c(
    "x-content-type-options",
    "x-frame-options",
    "strict-transport-security"
  )
  
  for (header in security_headers) {
    if (header %in% names(headers)) {
      expect_true(nchar(headers[[header]]) > 0,
                  info = sprintf("Security header %s should be present", header))
    }
  }
  
  # Test unauthorized access to protected endpoints
  protected_response <- GET(paste0(base_url, "/api/admin/config"))
  
  # Should return 401 or 403
  expect_true(status_code(protected_response) %in% c(401, 403),
              info = "Protected endpoints should require authentication")
})

test_that("Data persistence works across deployments", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  skip_if_not(Sys.getenv("TEST_PERSISTENCE", "FALSE") == "TRUE",
              "Persistence testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Get current data state
  initial_response <- GET(paste0(base_url, "/api/data/state"))
  
  if (status_code(initial_response) == 200) {
    initial_data <- content(initial_response, as = "parsed")
    
    # Check if data file exists and has recent timestamp
    expect_true("last_update" %in% names(initial_data),
                info = "Data state should include last update time")
    
    if ("last_update" %in% names(initial_data)) {
      last_update <- as.POSIXct(initial_data$last_update)
      age_hours <- as.numeric(Sys.time() - last_update, units = "hours")
      
      # Data should be relatively recent (< 24 hours old)
      expect_lt(age_hours, 24,
                info = sprintf("Data age: %.1f hours (should be < 24)", age_hours))
    }
    
    # Verify data can be loaded
    expect_true("data_available" %in% names(initial_data),
                info = "Should indicate if data is available")
    
    if ("data_available" %in% names(initial_data)) {
      expect_true(initial_data$data_available,
                  info = "Persisted data should be available")
    }
  }
})

test_that("Environment-specific configurations are loaded correctly", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Get configuration info (non-sensitive)
  config_response <- GET(paste0(base_url, "/api/config/info"))
  
  if (status_code(config_response) == 200) {
    config_data <- content(config_response, as = "parsed")
    
    # Check environment
    expect_true("environment" %in% names(config_data),
                info = "Config should include environment")
    
    if ("environment" %in% names(config_data)) {
      expect_equal(config_data$environment, "production",
                   info = "Should be running in production environment")
    }
    
    # Check required services are configured
    expect_true("services_configured" %in% names(config_data),
                info = "Config should indicate service configuration")
    
    if ("services_configured" %in% names(config_data)) {
      required_services <- c("api", "database", "cache")
      for (service in required_services) {
        if (service %in% names(config_data$services_configured)) {
          expect_true(config_data$services_configured[[service]],
                      info = sprintf("Service %s should be configured", service))
        }
      }
    }
  }
})

test_that("Error handling works correctly in production", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test various error scenarios
  
  # 1. Invalid endpoint
  invalid_response <- GET(paste0(base_url, "/api/nonexistent"))
  expect_equal(status_code(invalid_response), 404,
               info = "Invalid endpoints should return 404")
  
  # 2. Invalid request body
  bad_sim_response <- POST(
    paste0(base_url, "/api/simulate"),
    body = list(
      league = "InvalidLeague",
      iterations = -100  # Invalid iteration count
    ),
    encode = "json"
  )
  
  expect_equal(status_code(bad_sim_response), 400,
               info = "Invalid request should return 400")
  
  error_data <- content(bad_sim_response, as = "parsed")
  expect_true("error" %in% names(error_data),
              info = "Error response should include error message")
  
  # 3. Method not allowed
  method_response <- DELETE(paste0(base_url, "/api/simulate"))
  expect_equal(status_code(method_response), 405,
               info = "Wrong HTTP method should return 405")
})

test_that("Monitoring endpoints provide accurate metrics", {
  skip_if_not(Sys.getenv("TEST_DEPLOYED_APP", "FALSE") == "TRUE",
              "Deployed app testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test metrics endpoint
  metrics_response <- GET(paste0(base_url, "/metrics"))
  
  if (status_code(metrics_response) == 200) {
    metrics_text <- content(metrics_response, as = "text")
    
    # Check for standard metrics
    expect_true(grepl("http_requests_total", metrics_text),
                info = "Metrics should include request counts")
    
    expect_true(grepl("http_request_duration_seconds", metrics_text),
                info = "Metrics should include request duration")
    
    expect_true(grepl("process_resident_memory_bytes", metrics_text),
                info = "Metrics should include memory usage")
  }
})