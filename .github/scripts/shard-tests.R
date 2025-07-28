#!/usr/bin/env Rscript
# Shard tests for parallel execution

# Function to calculate test complexity/duration estimate
estimate_test_duration <- function(test_file) {
  # Simple heuristic based on file size and content
  size <- file.info(test_file)$size
  content <- readLines(test_file, warn = FALSE)
  
  # Count test_that calls
  n_tests <- sum(grepl("^\\s*test_that\\(", content))
  
  # Check for expensive operations
  has_simulation <- any(grepl("simulate|SpielNichtSimulieren", content, ignore.case = TRUE))
  has_api_calls <- any(grepl("httr::|api|retrieve", content, ignore.case = TRUE))
  has_loops <- any(grepl("for\\s*\\(|while\\s*\\(", content))
  
  # Calculate weight
  weight <- n_tests
  if (has_simulation) weight <- weight * 3
  if (has_api_calls) weight <- weight * 2
  if (has_loops) weight <- weight * 1.5
  
  return(weight)
}

# Function to distribute tests across shards
distribute_tests <- function(test_files, n_shards) {
  # Calculate weights for all tests
  test_weights <- sapply(test_files, estimate_test_duration)
  test_df <- data.frame(
    file = test_files,
    weight = test_weights,
    stringsAsFactors = FALSE
  )
  
  # Sort by weight (descending) for better distribution
  test_df <- test_df[order(test_df$weight, decreasing = TRUE), ]
  
  # Initialize shards
  shards <- vector("list", n_shards)
  shard_weights <- numeric(n_shards)
  
  # Distribute tests using greedy algorithm
  for (i in seq_len(nrow(test_df))) {
    # Find shard with minimum weight
    min_shard <- which.min(shard_weights)
    
    # Add test to that shard
    shards[[min_shard]] <- c(shards[[min_shard]], test_df$file[i])
    shard_weights[min_shard] <- shard_weights[min_shard] + test_df$weight[i]
  }
  
  return(shards)
}

# Main execution
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) < 2) {
    cat("Usage: shard-tests.R <n_shards> <test_dir>\n")
    quit(status = 1)
  }
  
  n_shards <- as.integer(args[1])
  test_dir <- args[2]
  
  # Get all test files
  test_files <- list.files(test_dir, pattern = "^test.*\\.R$", full.names = TRUE)
  
  if (length(test_files) == 0) {
    cat("No test files found in", test_dir, "\n")
    quit(status = 1)
  }
  
  # Distribute tests
  shards <- distribute_tests(test_files, n_shards)
  
  # Output for GitHub Actions matrix
  if (nchar(Sys.getenv("GITHUB_OUTPUT")) > 0) {
    output_file <- Sys.getenv("GITHUB_OUTPUT")
    
    # Create matrix JSON
    matrix_json <- jsonlite::toJSON(list(
      shard = seq_len(n_shards),
      tests = shards
    ), auto_unbox = TRUE)
    
    cat(sprintf("matrix=%s\n", matrix_json), file = output_file, append = TRUE)
  }
  
  # Display shard distribution
  cat("\nTest Distribution Across Shards:\n")
  for (i in seq_len(n_shards)) {
    cat(sprintf("\nShard %d (%d tests):\n", i, length(shards[[i]])))
    for (test in shards[[i]]) {
      cat(sprintf("  - %s\n", basename(test)))
    }
  }
  
  # Calculate balance metric
  weights_per_shard <- sapply(seq_len(n_shards), function(i) {
    sum(sapply(shards[[i]], estimate_test_duration))
  })
  
  balance_ratio <- max(weights_per_shard) / mean(weights_per_shard)
  cat(sprintf("\nBalance Ratio: %.2f (lower is better, 1.0 is perfect)\n", balance_ratio))
}