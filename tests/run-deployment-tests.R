#!/usr/bin/env Rscript

# Deployment Test Runner for CI/CD
# This script orchestrates the execution of deployment safety tests

library(testthat)
library(jsonlite)

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  cat("Usage: Rscript run-deployment-tests.R <test-suite> [environment]\n")
  cat("Test suites: all, pre-deployment, performance, integration, security, chaos\n")
  cat("Environments: local, staging, production\n")
  quit(status = 1)
}

test_suite <- args[1]
environment <- ifelse(length(args) >= 2, args[2], "local")

# Set environment variables based on target
Sys.setenv(
  TEST_ENVIRONMENT = environment,
  TEST_HEALTH_ENDPOINTS = "TRUE",
  TEST_DEPLOYED_APP = ifelse(environment != "local", "TRUE", "FALSE")
)

# Configure test settings
test_config <- list(
  environment = environment,
  timestamp = Sys.time(),
  results = list()
)

# Helper function to run test suite
run_test_suite <- function(suite_name, test_files) {
  cat(sprintf("\n=== Running %s tests ===\n", suite_name))
  
  suite_results <- list(
    suite = suite_name,
    start_time = Sys.time(),
    tests = list()
  )
  
  for (test_file in test_files) {
    if (file.exists(test_file)) {
      cat(sprintf("Running: %s\n", basename(test_file)))
      
      # Capture test results
      test_result <- tryCatch({
        test_output <- capture.output({
          test_results <- test_file(test_file)
        })
        
        list(
          file = test_file,
          passed = sum(as.data.frame(test_results)$passed, na.rm = TRUE),
          failed = sum(as.data.frame(test_results)$failed, na.rm = TRUE),
          skipped = sum(as.data.frame(test_results)$skipped, na.rm = TRUE),
          warnings = sum(as.data.frame(test_results)$warning, na.rm = TRUE),
          output = test_output
        )
      }, error = function(e) {
        list(
          file = test_file,
          error = as.character(e),
          passed = 0,
          failed = 1,
          skipped = 0,
          warnings = 0
        )
      })
      
      suite_results$tests[[basename(test_file)]] <- test_result
    } else {
      cat(sprintf("Warning: Test file not found: %s\n", test_file))
    }
  }
  
  suite_results$end_time <- Sys.time()
  suite_results$duration <- as.numeric(suite_results$end_time - suite_results$start_time, units = "secs")
  
  # Calculate totals
  suite_results$totals <- list(
    passed = sum(sapply(suite_results$tests, function(x) x$passed)),
    failed = sum(sapply(suite_results$tests, function(x) x$failed)),
    skipped = sum(sapply(suite_results$tests, function(x) x$skipped)),
    warnings = sum(sapply(suite_results$tests, function(x) x$warnings))
  )
  
  return(suite_results)
}

# Define test suites
test_suites <- list(
  "pre-deployment" = c(
    "deployment/pre-deployment/test_preflight_checks.R",
    "deployment/pre-deployment/test_health_checks.R"
  ),
  "performance" = c(
    "deployment/post-deployment/test_performance_validation.R",
    "deployment/deployment/test_deployment_performance.R"
  ),
  "integration" = c(
    "deployment/post-deployment/test_integration_smoke.R",
    "deployment/deployment/test_deployment_workflow.R"
  ),
  "security" = c(
    "security/test_security_validation.R",
    "security/test_compliance.R"
  ),
  "chaos" = c(
    "resilience/test_chaos_engineering.R",
    "resilience/test_failure_injection.R"
  ),
  "deployment" = c(
    "deployment/deployment/test_k8s_deployment.R",
    "deployment/rollback/test_rollback_safety.R"
  )
)

# Determine which suites to run
suites_to_run <- if (test_suite == "all") {
  names(test_suites)
} else if (test_suite %in% names(test_suites)) {
  test_suite
} else {
  stop(sprintf("Unknown test suite: %s", test_suite))
}

# Run selected test suites
for (suite in suites_to_run) {
  suite_results <- run_test_suite(suite, test_suites[[suite]])
  test_config$results[[suite]] <- suite_results
  
  # Print summary
  cat(sprintf("\n%s summary: %d passed, %d failed, %d skipped\n",
              suite,
              suite_results$totals$passed,
              suite_results$totals$failed,
              suite_results$totals$skipped))
}

# Generate overall summary
overall_totals <- list(
  passed = sum(sapply(test_config$results, function(x) x$totals$passed)),
  failed = sum(sapply(test_config$results, function(x) x$totals$failed)),
  skipped = sum(sapply(test_config$results, function(x) x$totals$skipped)),
  warnings = sum(sapply(test_config$results, function(x) x$totals$warnings))
)

test_config$overall <- overall_totals
test_config$end_time <- Sys.time()
test_config$total_duration <- as.numeric(test_config$end_time - test_config$timestamp, units = "secs")

# Save results
results_dir <- "deployment-test-results"
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

results_file <- file.path(results_dir, 
                         sprintf("results_%s_%s.json", 
                                 test_suite,
                                 format(test_config$timestamp, "%Y%m%d_%H%M%S")))

write_json(test_config, results_file, pretty = TRUE, auto_unbox = TRUE)

# Print final summary
cat("\n", paste(rep("=", 50), collapse = ""), "\n", sep = "")
cat("DEPLOYMENT TEST SUMMARY\n")
cat(paste(rep("=", 50), collapse = ""), "\n", sep = "")
cat(sprintf("Environment: %s\n", environment))
cat(sprintf("Test Suite: %s\n", test_suite))
cat(sprintf("Duration: %.1f seconds\n", test_config$total_duration))
cat(sprintf("\nResults:\n"))
cat(sprintf("  ✓ Passed:  %d\n", overall_totals$passed))
cat(sprintf("  ✗ Failed:  %d\n", overall_totals$failed))
cat(sprintf("  ⊘ Skipped: %d\n", overall_totals$skipped))
cat(sprintf("  ⚠ Warnings: %d\n", overall_totals$warnings))
cat(sprintf("\nResults saved to: %s\n", results_file))

# Exit with appropriate code
exit_code <- ifelse(overall_totals$failed > 0, 1, 0)

# Generate JUnit XML for CI/CD integration
if (Sys.getenv("CI") == "true") {
  junit_file <- file.path(results_dir, 
                         sprintf("junit_%s_%s.xml", 
                                 test_suite,
                                 format(test_config$timestamp, "%Y%m%d_%H%M%S")))
  
  # Simple JUnit XML generation (would use proper XML library in production)
  junit_xml <- sprintf('<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Deployment Safety Tests" tests="%d" failures="%d" skipped="%d" time="%.2f">
  <testsuite name="%s" tests="%d" failures="%d" skipped="%d" time="%.2f">
    <properties>
      <property name="environment" value="%s"/>
    </properties>
  </testsuite>
</testsuites>',
    overall_totals$passed + overall_totals$failed + overall_totals$skipped,
    overall_totals$failed,
    overall_totals$skipped,
    test_config$total_duration,
    test_suite,
    overall_totals$passed + overall_totals$failed + overall_totals$skipped,
    overall_totals$failed,
    overall_totals$skipped,
    test_config$total_duration,
    environment
  )
  
  writeLines(junit_xml, junit_file)
  cat(sprintf("JUnit results saved to: %s\n", junit_file))
}

quit(status = exit_code)