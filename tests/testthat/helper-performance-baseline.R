# Performance Baseline Tracking System
# Helper functions for tracking and comparing performance against historical baselines

library(jsonlite)

# Load baseline data
load_baseline <- function(baseline_file = "tests/performance/baselines/empirical_baseline.json") {
  if (!file.exists(baseline_file)) {
    stop("Baseline file not found. Run tests/performance/measure-baselines.R first.")
  }
  fromJSON(baseline_file)
}

# Compare current performance against baseline
compare_to_baseline <- function(current_time_ms, baseline_time_ms, tolerance = 1.1) {
  ratio <- current_time_ms / baseline_time_ms
  list(
    current = current_time_ms,
    baseline = baseline_time_ms,
    ratio = ratio,
    within_tolerance = ratio <= tolerance,
    percent_change = (ratio - 1) * 100
  )
}

# Update baseline if performance improves
update_baseline_if_faster <- function(baseline_file, test_name, new_time_ms) {
  baseline <- load_baseline(baseline_file)
  
  # Navigate to the correct test result
  parts <- strsplit(test_name, "\\.")[[1]]
  current_value <- baseline
  for (part in parts[1:(length(parts)-1)]) {
    current_value <- current_value[[part]]
  }
  
  old_time <- as.numeric(current_value[[parts[length(parts)]]])
  
  if (new_time_ms < old_time * 0.95) {  # Only update if 5% faster
    # Update the baseline
    current_value[[parts[length(parts)]]] <- new_time_ms
    
    # Add update metadata
    if (is.null(baseline$update_history)) {
      baseline$update_history <- list()
    }
    
    baseline$update_history[[length(baseline$update_history) + 1]] <- list(
      test = test_name,
      old_value = old_time,
      new_value = new_time_ms,
      improvement_pct = ((old_time - new_time_ms) / old_time) * 100,
      timestamp = Sys.time()
    )
    
    # Write updated baseline
    write_json(baseline, baseline_file, pretty = TRUE, auto_unbox = TRUE)
    
    return(list(updated = TRUE, old = old_time, new = new_time_ms))
  }
  
  return(list(updated = FALSE, current = old_time))
}

# Performance expectation helpers
expect_performance <- function(time_ms, baseline_ms, tolerance = 1.1, test_name = NULL) {
  comparison <- compare_to_baseline(time_ms, baseline_ms, tolerance)
  
  if (!comparison$within_tolerance) {
    msg <- sprintf(
      "Performance regression detected%s: %.1fms (current) vs %.1fms (baseline). %.1f%% slower.",
      ifelse(is.null(test_name), "", paste0(" in ", test_name)),
      comparison$current,
      comparison$baseline,
      comparison$percent_change
    )
    stop(msg)
  }
  
  invisible(comparison)
}

# Calculate expected time based on empirical formula
calculate_expected_time <- function(iterations, games_to_simulate, 
                                   time_per_iter_game = 0.0157, 
                                   base_overhead = 20) {
  base_overhead + (iterations * games_to_simulate * time_per_iter_game)
}

# Verify O(N) scaling
verify_linear_scaling <- function(times, counts, tolerance = 0.2) {
  # Calculate scaling factors
  scaling_factors <- numeric(length(times) - 1)
  
  for (i in 2:length(times)) {
    time_ratio <- times[i] / times[i-1]
    count_ratio <- counts[i] / counts[i-1]
    scaling_factors[i-1] <- time_ratio / count_ratio
  }
  
  # Check if scaling is approximately linear (factor should be close to 1)
  mean_factor <- mean(scaling_factors)
  deviation <- abs(mean_factor - 1)
  
  list(
    scaling_factors = scaling_factors,
    mean_factor = mean_factor,
    is_linear = deviation <= tolerance,
    deviation = deviation
  )
}

# Generate performance report
generate_performance_report <- function(test_results) {
  baseline <- load_baseline()
  
  report <- list(
    timestamp = Sys.time(),
    system = baseline$system_info,
    test_results = test_results,
    baseline_comparison = list()
  )
  
  # Compare each test result to baseline
  for (test_name in names(test_results)) {
    if (test_name %in% names(baseline$iteration_scaling)) {
      baseline_value <- baseline$iteration_scaling[[test_name]]
      current_value <- test_results[[test_name]]
      
      report$baseline_comparison[[test_name]] <- compare_to_baseline(
        current_value, 
        baseline_value,
        tolerance = 1.1
      )
    }
  }
  
  # Save report
  report_file <- sprintf("tests/performance/reports/perf_report_%s.json",
                        format(Sys.time(), "%Y%m%d_%H%M%S"))
  dir.create("tests/performance/reports", recursive = TRUE, showWarnings = FALSE)
  write_json(report, report_file, pretty = TRUE, auto_unbox = TRUE)
  
  return(report)
}

# Helper to run performance test with baseline comparison
run_performance_test <- function(test_func, test_name, times = 5, 
                                baseline_file = "tests/performance/baselines/empirical_baseline.json") {
  
  # Load baseline
  baseline <- load_baseline(baseline_file)
  
  # Run the test
  timing <- microbenchmark(test_func(), times = times)
  median_time <- median(timing$time) / 1e6  # Convert to ms
  
  # Get baseline value (navigate through nested structure)
  baseline_value <- NULL
  parts <- strsplit(test_name, "\\.")[[1]]
  current <- baseline
  
  for (part in parts) {
    if (!is.null(current[[part]])) {
      current <- current[[part]]
    } else {
      break
    }
  }
  
  if (is.numeric(current)) {
    baseline_value <- current
  }
  
  # Compare to baseline if available
  if (!is.null(baseline_value)) {
    comparison <- compare_to_baseline(median_time, baseline_value)
    
    # Check for regression
    if (!comparison$within_tolerance) {
      warning(sprintf(
        "Performance regression in %s: %.1fms (%.1f%% slower than baseline %.1fms)",
        test_name, median_time, comparison$percent_change, baseline_value
      ))
    }
    
    # Check for improvement
    if (comparison$ratio < 0.95) {
      message(sprintf(
        "Performance improvement in %s: %.1fms (%.1f%% faster than baseline %.1fms)",
        test_name, median_time, abs(comparison$percent_change), baseline_value
      ))
    }
    
    return(list(
      test = test_name,
      median_ms = median_time,
      baseline_ms = baseline_value,
      comparison = comparison,
      raw_times = timing$time / 1e6
    ))
  } else {
    return(list(
      test = test_name,
      median_ms = median_time,
      baseline_ms = NA,
      comparison = NA,
      raw_times = timing$time / 1e6
    ))
  }
}