#!/usr/bin/env Rscript

# Truly comprehensive test runner for ALL tests

cat("=== League Simulator FULL Test Suite ===\n\n")

# Load required libraries
library(Rcpp)
library(testthat)

# Compile C++ code
cat("Step 1: Compiling C++ code...\n")
tryCatch({
  sourceCpp("RCode/SpielNichtSimulieren.cpp")
  cat("✓ C++ compilation successful\n\n")
}, error = function(e) {
  cat("✗ C++ compilation failed:", e$message, "\n")
  quit(status = 1)
})

# Get ALL test files
cat("Step 2: Finding all test files...\n")
all_test_files <- list.files("tests/testthat", pattern = "^test-.*\\.R$", full.names = FALSE)
all_test_files <- grep("\\.bak$", all_test_files, value = TRUE, invert = TRUE)
cat("Found", length(all_test_files), "test files\n\n")

cat("Step 3: Running ALL tests...\n\n")

# Run each test file
total_passed <- 0
total_failed <- 0
total_skipped <- 0
failed_tests <- list()
test_results <- list()

for (test_file in all_test_files) {
  cat(sprintf("%-40s", paste0("Testing ", test_file, " ...")))
  
  # Capture output to avoid clutter
  result <- tryCatch({
    suppressMessages({
      test_file(file.path("tests/testthat", test_file), reporter = "silent")
    })
  }, error = function(e) {
    list(failed = 1, passed = 0, skipped = 0, error = e$message)
  })
  
  if (!is.null(result)) {
    passed <- if("passed" %in% names(result)) sum(result$passed) else 0
    failed <- if("failed" %in% names(result)) sum(result$failed) else 0
    skipped <- if("skipped" %in% names(result)) sum(result$skipped) else 0
    
    total_passed <- total_passed + passed
    total_failed <- total_failed + failed
    total_skipped <- total_skipped + skipped
    
    test_results[[test_file]] <- list(
      passed = passed,
      failed = failed,
      skipped = skipped,
      error = if("error" %in% names(result)) result$error else NULL
    )
    
    if (failed > 0) {
      cat(sprintf("✗ %d failures\n", failed))
      failed_tests[[test_file]] <- failed
    } else if (!is.null(result$error)) {
      cat("✗ Error:", result$error, "\n")
      failed_tests[[test_file]] <- 1
    } else {
      cat(sprintf("✓ %d passed", passed))
      if (skipped > 0) cat(sprintf(", %d skipped", skipped))
      cat("\n")
    }
  }
}

# Detailed Summary
cat("\n=== Detailed Test Summary ===\n")
cat("Total tests passed:  ", total_passed, "\n")
cat("Total tests failed:  ", total_failed, "\n")
cat("Total tests skipped: ", total_skipped, "\n")
cat("Total test files:    ", length(all_test_files), "\n")

if (total_failed > 0) {
  cat("\n=== Failed Tests by File ===\n")
  for (file in names(failed_tests)) {
    result <- test_results[[file]]
    cat(sprintf("- %-35s %d failures", file, failed_tests[[file]]))
    if (!is.null(result$error)) {
      cat(" (", substr(result$error, 1, 50), "...)")
    }
    cat("\n")
  }
  
  cat("\n=== Known Issues ===\n")
  cat("1. Parameter name mismatches (ModFaktor vs modFactor) in some tests\n")
  cat("2. Some tests depend on helper functions that need to be sourced\n")
  cat("3. Interactive tests may hang waiting for input\n")
} else {
  cat("\n✓ All tests passed successfully!\n")
}

# Show which tests are working well
cat("\n=== Working Tests ===\n")
for (file in names(test_results)) {
  result <- test_results[[file]]
  if (result$failed == 0 && result$passed > 0) {
    cat(sprintf("✓ %-35s %d tests\n", file, result$passed))
  }
}

# Return appropriate exit code
quit(status = ifelse(total_failed > 0, 1, 0))