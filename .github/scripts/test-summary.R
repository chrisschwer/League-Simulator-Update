#!/usr/bin/env Rscript
# Generate test summary report for GitHub Actions

library(testthat)

# Function to categorize test failures
categorize_failure <- function(error_message) {
  if (grepl("API|connection|timeout|network", error_message, ignore.case = TRUE)) {
    return("Infrastructure")
  } else if (grepl("memory|allocation|stack", error_message, ignore.case = TRUE)) {
    return("Resource")
  } else if (grepl("permission|access denied|file not found", error_message, ignore.case = TRUE)) {
    return("Permissions")
  } else {
    return("Code")
  }
}

# Generate markdown summary
generate_summary <- function(test_results) {
  summary <- "## Test Execution Summary\n\n"
  
  total_tests <- 0
  passed_tests <- 0
  failed_tests <- 0
  skipped_tests <- 0
  
  failure_categories <- list()
  
  if (!is.null(test_results$results)) {
    for (result in test_results$results) {
      total_tests <- total_tests + 1
      
      if (!is.null(result$error) || !is.null(result$failure)) {
        failed_tests <- failed_tests + 1
        error_msg <- result$error %||% result$failure
        category <- categorize_failure(as.character(error_msg))
        failure_categories[[category]] <- (failure_categories[[category]] %||% 0) + 1
      } else if (!is.null(result$skip)) {
        skipped_tests <- skipped_tests + 1
      } else {
        passed_tests <- passed_tests + 1
      }
    }
  }
  
  # Overall statistics
  summary <- paste0(summary, "### Overall Results\n")
  summary <- paste0(summary, sprintf("- Total Tests: %d\n", total_tests))
  summary <- paste0(summary, sprintf("- Passed: %d (%.1f%%)\n", passed_tests, 100 * passed_tests / max(total_tests, 1)))
  summary <- paste0(summary, sprintf("- Failed: %d (%.1f%%)\n", failed_tests, 100 * failed_tests / max(total_tests, 1)))
  summary <- paste0(summary, sprintf("- Skipped: %d (%.1f%%)\n", skipped_tests, 100 * skipped_tests / max(total_tests, 1)))
  summary <- paste0(summary, "\n")
  
  # Failure categorization
  if (failed_tests > 0) {
    summary <- paste0(summary, "### Failure Categories\n")
    for (category in names(failure_categories)) {
      count <- failure_categories[[category]]
      summary <- paste0(summary, sprintf("- %s: %d failures\n", category, count))
    }
    summary <- paste0(summary, "\n")
  }
  
  # Recommendations
  summary <- paste0(summary, "### Recommendations\n")
  if (failed_tests == 0) {
    summary <- paste0(summary, "✅ All tests passed! Consider reducing the failure threshold.\n")
  } else {
    if ("Infrastructure" %in% names(failure_categories) && failure_categories[["Infrastructure"]] > 0) {
      summary <- paste0(summary, "⚠️ Infrastructure failures detected - consider retry logic or environment fixes\n")
    }
    if ("Resource" %in% names(failure_categories) && failure_categories[["Resource"]] > 0) {
      summary <- paste0(summary, "⚠️ Resource constraints detected - consider larger runners or optimizing memory usage\n")
    }
    if ("Code" %in% names(failure_categories) && failure_categories[["Code"]] > 0) {
      summary <- paste0(summary, "🐛 Code failures detected - these need to be fixed in the implementation\n")
    }
  }
  
  return(summary)
}

# Main execution
if (exists("test_results") && !is.null(test_results)) {
  summary <- generate_summary(test_results)
  
  # Write to GitHub step summary if available
  github_step_summary <- Sys.getenv("GITHUB_STEP_SUMMARY")
  if (nchar(github_step_summary) > 0) {
    cat(summary, file = github_step_summary, append = TRUE)
  }
  
  # Also output to console
  cat(summary)
} else {
  cat("No test results available for summary generation\n")
}