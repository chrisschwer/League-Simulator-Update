#!/usr/bin/env Rscript
# Detect and quarantine flaky tests

library(jsonlite)

# Function to analyze test history
analyze_test_history <- function(test_name, history_file = ".github/test-history.json") {
  history <- list()
  
  if (file.exists(history_file)) {
    history <- fromJSON(history_file)
  }
  
  if (is.null(history[[test_name]])) {
    return(list(
      flakiness_score = 0,
      total_runs = 0,
      failure_rate = 0,
      consecutive_failures = 0,
      is_flaky = FALSE
    ))
  }
  
  test_history <- history[[test_name]]
  total_runs <- length(test_history$results)
  
  if (total_runs < 5) {
    # Not enough data
    return(list(
      flakiness_score = 0,
      total_runs = total_runs,
      failure_rate = 0,
      consecutive_failures = 0,
      is_flaky = FALSE
    ))
  }
  
  # Calculate metrics
  failures <- sum(test_history$results == "fail")
  failure_rate <- failures / total_runs
  
  # Check for alternating pass/fail pattern (high flakiness indicator)
  alternations <- 0
  for (i in 2:length(test_history$results)) {
    if (test_history$results[i] != test_history$results[i-1]) {
      alternations <- alternations + 1
    }
  }
  alternation_rate <- alternations / (total_runs - 1)
  
  # Count consecutive failures
  consecutive_failures <- 0
  current_streak <- 0
  for (result in rev(test_history$results)) {
    if (result == "fail") {
      current_streak <- current_streak + 1
      consecutive_failures <- max(consecutive_failures, current_streak)
    } else {
      current_streak <- 0
    }
  }
  
  # Calculate flakiness score
  flakiness_score <- 0
  
  # High alternation rate indicates flakiness
  if (alternation_rate > 0.3) {
    flakiness_score <- flakiness_score + 40
  }
  
  # Moderate failure rate with some passes indicates flakiness
  if (failure_rate > 0.2 && failure_rate < 0.8) {
    flakiness_score <- flakiness_score + 30
  }
  
  # Recent instability
  recent_results <- tail(test_history$results, 10)
  recent_failures <- sum(recent_results == "fail")
  if (recent_failures > 2 && recent_failures < 8) {
    flakiness_score <- flakiness_score + 30
  }
  
  is_flaky <- flakiness_score >= 50
  
  return(list(
    flakiness_score = flakiness_score,
    total_runs = total_runs,
    failure_rate = failure_rate,
    consecutive_failures = consecutive_failures,
    alternation_rate = alternation_rate,
    is_flaky = is_flaky
  ))
}

# Function to update test history
update_test_history <- function(test_name, result, history_file = ".github/test-history.json") {
  history <- list()
  
  if (file.exists(history_file)) {
    history <- fromJSON(history_file)
  }
  
  if (is.null(history[[test_name]])) {
    history[[test_name]] <- list(
      results = character(),
      timestamps = character()
    )
  }
  
  # Add new result
  history[[test_name]]$results <- c(history[[test_name]]$results, result)
  history[[test_name]]$timestamps <- c(history[[test_name]]$timestamps, 
                                      format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  
  # Keep only last 50 results
  if (length(history[[test_name]]$results) > 50) {
    history[[test_name]]$results <- tail(history[[test_name]]$results, 50)
    history[[test_name]]$timestamps <- tail(history[[test_name]]$timestamps, 50)
  }
  
  # Save updated history
  write(toJSON(history, pretty = TRUE), history_file)
}

# Function to generate flaky test report
generate_flaky_test_report <- function(history_file = ".github/test-history.json") {
  if (!file.exists(history_file)) {
    cat("No test history found\n")
    return(invisible())
  }
  
  history <- fromJSON(history_file)
  
  flaky_tests <- list()
  stable_failures <- list()
  
  for (test_name in names(history)) {
    analysis <- analyze_test_history(test_name, history_file)
    
    if (analysis$is_flaky) {
      flaky_tests[[test_name]] <- analysis
    } else if (analysis$failure_rate > 0.8 && analysis$total_runs >= 5) {
      stable_failures[[test_name]] <- analysis
    }
  }
  
  # Generate report
  cat("# Test Stability Report\n\n")
  
  if (length(flaky_tests) > 0) {
    cat("## Flaky Tests (Should be quarantined)\n\n")
    for (test_name in names(flaky_tests)) {
      test <- flaky_tests[[test_name]]
      cat(sprintf("- **%s**\n", test_name))
      cat(sprintf("  - Flakiness Score: %d/100\n", test$flakiness_score))
      cat(sprintf("  - Failure Rate: %.1f%%\n", test$failure_rate * 100))
      cat(sprintf("  - Alternation Rate: %.1f%%\n", test$alternation_rate * 100))
      cat(sprintf("  - Total Runs: %d\n", test$total_runs))
      cat("\n")
    }
  } else {
    cat("## No flaky tests detected\n\n")
  }
  
  if (length(stable_failures) > 0) {
    cat("## Consistently Failing Tests (Need fixes)\n\n")
    for (test_name in names(stable_failures)) {
      test <- stable_failures[[test_name]]
      cat(sprintf("- **%s**\n", test_name))
      cat(sprintf("  - Failure Rate: %.1f%%\n", test$failure_rate * 100))
      cat(sprintf("  - Consecutive Failures: %d\n", test$consecutive_failures))
      cat(sprintf("  - Total Runs: %d\n", test$total_runs))
      cat("\n")
    }
  }
  
  # Create quarantine file
  if (length(flaky_tests) > 0) {
    quarantine <- data.frame(
      test = names(flaky_tests),
      reason = "flaky",
      score = sapply(flaky_tests, function(x) x$flakiness_score),
      stringsAsFactors = FALSE
    )
    write.csv(quarantine, ".github/quarantined-tests.csv", row.names = FALSE)
  }
}

# Main execution
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) == 0) {
    cat("Usage: flaky-test-detector.R <command> [args...]\n")
    cat("Commands:\n")
    cat("  update <test_name> <pass|fail> - Update test history\n")
    cat("  analyze <test_name> - Analyze specific test\n")
    cat("  report - Generate flaky test report\n")
    quit(status = 1)
  }
  
  command <- args[1]
  
  if (command == "update" && length(args) >= 3) {
    test_name <- args[2]
    result <- args[3]
    update_test_history(test_name, result)
    
    # Check if test is now flaky
    analysis <- analyze_test_history(test_name)
    if (analysis$is_flaky) {
      cat(sprintf("WARNING: Test '%s' is now considered flaky (score: %d)\n", 
                  test_name, analysis$flakiness_score))
    }
    
  } else if (command == "analyze" && length(args) >= 2) {
    test_name <- args[2]
    analysis <- analyze_test_history(test_name)
    
    cat(sprintf("Test: %s\n", test_name))
    cat(sprintf("Flakiness Score: %d/100\n", analysis$flakiness_score))
    cat(sprintf("Total Runs: %d\n", analysis$total_runs))
    cat(sprintf("Failure Rate: %.1f%%\n", analysis$failure_rate * 100))
    cat(sprintf("Is Flaky: %s\n", if(analysis$is_flaky) "YES" else "NO"))
    
  } else if (command == "report") {
    generate_flaky_test_report()
    
  } else {
    cat("Invalid command or arguments\n")
    quit(status = 1)
  }
}