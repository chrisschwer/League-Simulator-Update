# Health Check Endpoints for League Simulator
# This module provides health, readiness, and liveness endpoints

library(jsonlite)

# Initialize health check module
init_health_checks <- function() {
  # Store initialization time
  .GlobalEnv$.health_init_time <- Sys.time()
  .GlobalEnv$.health_version <- list(
    app = "1.0.0",
    api = "v1"
  )
}

# Main health check function
perform_health_check <- function() {
  start_time <- Sys.time()
  
  health_status <- list(
    status = "healthy",
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    uptime_seconds = as.numeric(Sys.time() - .GlobalEnv$.health_init_time, units = "secs"),
    checks = list(),
    version = .GlobalEnv$.health_version
  )
  
  # Check database/data file access
  data_check <- tryCatch({
    if (file.exists("data/Ergebnis.Rds")) {
      file_info <- file.info("data/Ergebnis.Rds")
      list(
        healthy = TRUE,
        last_modified = format(file_info$mtime, "%Y-%m-%d %H:%M:%S"),
        size_bytes = file_info$size
      )
    } else {
      list(healthy = FALSE, error = "Data file not found")
    }
  }, error = function(e) {
    list(healthy = FALSE, error = as.character(e))
  })
  
  health_status$checks$database <- data_check
  
  # Check API connectivity (mock check - real implementation would test actual API)
  api_check <- tryCatch({
    api_key <- Sys.getenv("RAPIDAPI_KEY")
    list(
      healthy = nchar(api_key) > 0,
      configured = nchar(api_key) > 0
    )
  }, error = function(e) {
    list(healthy = FALSE, error = as.character(e))
  })
  
  health_status$checks$api <- api_check
  
  # Check filesystem write permissions
  fs_check <- tryCatch({
    test_file <- tempfile()
    writeLines("test", test_file)
    unlink(test_file)
    list(healthy = TRUE, writable = TRUE)
  }, error = function(e) {
    list(healthy = FALSE, error = as.character(e))
  })
  
  health_status$checks$filesystem <- fs_check
  
  # Calculate overall health
  all_healthy <- all(sapply(health_status$checks, function(x) x$healthy))
  health_status$status <- ifelse(all_healthy, "healthy", "unhealthy")
  
  # Add response time
  health_status$response_time_ms <- as.numeric(Sys.time() - start_time, units = "secs") * 1000
  
  return(health_status)
}

# Readiness check function
perform_readiness_check <- function() {
  readiness <- list(
    ready = TRUE,
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    services = list()
  )
  
  # Check if data is loaded and recent
  data_service <- tryCatch({
    if (file.exists("data/Ergebnis.Rds")) {
      file_age <- as.numeric(Sys.time() - file.mtime("data/Ergebnis.Rds"), units = "hours")
      list(
        status = ifelse(file_age < 24, "ready", "stale"),
        age_hours = round(file_age, 2)
      )
    } else {
      list(status = "not_ready", error = "Data file missing")
    }
  }, error = function(e) {
    list(status = "error", error = as.character(e))
  })
  
  readiness$services$data <- data_service
  
  # Check Shiny app status
  shiny_service <- list(
    status = ifelse(exists("input", where = .GlobalEnv), "ready", "initializing")
  )
  
  readiness$services$shiny <- shiny_service
  
  # Determine overall readiness
  all_ready <- all(sapply(readiness$services, function(x) x$status %in% c("ready", "initializing")))
  readiness$ready <- all_ready
  
  return(readiness)
}

# Simple liveness check
perform_liveness_check <- function() {
  list(
    alive = TRUE,
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )
}

# Helper function to create JSON response
create_json_response <- function(data, status_code = 200) {
  list(
    status = status_code,
    headers = list("Content-Type" = "application/json"),
    body = toJSON(data, auto_unbox = TRUE, pretty = TRUE)
  )
}

# Export functions
health_endpoints <- list(
  init = init_health_checks,
  health = perform_health_check,
  ready = perform_readiness_check,
  alive = perform_liveness_check,
  json_response = create_json_response
)