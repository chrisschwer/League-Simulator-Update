#!/usr/bin/env Rscript

# Compare R's qpois() with Rust's poisson_quantile() implementation
# This test helps identify if Poisson distribution differences cause the 3.7% discrepancy

cat("=== Poisson Distribution Comparison: R vs Rust ===\n\n")

# Test parameters
p_values <- c(0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.99, 1.0)
lambda_values <- c(0.001, 0.5, 1.0, 1.3218390804597700, 2.0, 3.0, 5.0)  # Include ToreIntercept default

# Create test matrix
results <- data.frame()

cat("Generating R reference values...\n")
for (lambda in lambda_values) {
  for (p in p_values) {
    # R's qpois function
    r_result <- qpois(p, lambda)
    
    results <- rbind(results, data.frame(
      p = p,
      lambda = lambda,
      r_qpois = r_result
    ))
  }
}

# Save results for comparison
write.csv(results, "poisson_test_cases.csv", row.names = FALSE)
cat(sprintf("Generated %d test cases\n\n", nrow(results)))

# Display sample results
cat("Sample test cases (first 20):\n")
print(head(results, 20))

cat("\n=== Key Observations ===\n")

# Check typical goal generation scenarios
typical_lambda <- 1.3218390804597700  # ToreIntercept default
cat(sprintf("\nFor typical lambda = %.4f (ToreIntercept):\n", typical_lambda))
typical_results <- results[results$lambda == typical_lambda, ]
for (i in 1:nrow(typical_results)) {
  cat(sprintf("  p = %.2f: qpois = %.0f\n", typical_results$p[i], typical_results$r_qpois[i]))
}

# Check goal generation with ELO differences
# Example: Strong team (lambda = 2.0) vs Weak team (lambda = 0.8)
cat("\nStrong team scenario (lambda = 2.0):\n")
strong_results <- results[results$lambda == 2.0, ]
for (i in seq(1, nrow(strong_results), by = 2)) {
  cat(sprintf("  p = %.2f: qpois = %.0f\n", strong_results$p[i], strong_results$r_qpois[i]))
}

cat("\nWeak team scenario (lambda = 0.5):\n")
weak_results <- results[results$lambda == 0.5, ]
for (i in seq(1, nrow(weak_results), by = 2)) {
  cat(sprintf("  p = %.2f: qpois = %.0f\n", weak_results$p[i], weak_results$r_qpois[i]))
}

# Now test with Rust if available
if (file.exists("test_rust_poisson.R")) {
  cat("\n=== Testing Rust Implementation ===\n")
  source("test_rust_poisson.R")
} else {
  cat("\n=== Rust Comparison Script ===\n")
  cat("Create test_rust_poisson.R to compare with Rust implementation.\n")
  cat("The script should:\n")
  cat("1. Connect to Rust API\n")
  cat("2. Send each (p, lambda) pair to Rust's poisson_quantile\n")
  cat("3. Compare results with r_qpois column\n")
  cat("4. Report any discrepancies\n")
}

cat("\n✅ Poisson reference data generated!\n")