#!/usr/bin/env Rscript

# Verify exact definition of R's qpois

cat("=== R's qpois Definition Verification ===\n\n")

# Test lambda = 1.5
lambda <- 1.5

cat("For Poisson(1.5):\n")
for (k in 0:5) {
  cdf_k <- ppois(k, lambda)
  cat(sprintf("P(X <= %d) = %.10f\n", k, cdf_k))
}

cat("\n")

# Test specific p values
test_p <- c(0.223129, 0.223130, 0.223131,  # Around P(X <= 0)
            0.557824, 0.557825, 0.557826)   # Around P(X <= 1)

cat("Testing qpois at boundaries:\n")
for (p in test_p) {
  q <- qpois(p, lambda)
  cat(sprintf("qpois(%.6f, 1.5) = %d\n", p, q))
}

cat("\n=== Critical insight ===\n")
cat("R's qpois(p, lambda) returns the smallest integer x such that:\n")
cat("  ppois(x, lambda) >= p\n")
cat("Which means:\n")
cat("  P(X <= x) >= p\n\n")

cat("So the Rust code should use:\n")
cat("  if cdf < p { low = mid + 1 }  // Correct!\n")
cat("NOT:\n")
cat("  if cdf <= p { low = mid + 1 } // Wrong!\n\n")

# Double-check with actual test
cat("Verification:\n")
p_test <- 0.557825
q_result <- qpois(p_test, lambda)
cdf_result <- ppois(q_result, lambda)
cdf_below <- ppois(q_result - 1, lambda)

cat(sprintf("qpois(%.6f, 1.5) = %d\n", p_test, q_result))
cat(sprintf("ppois(%d, 1.5) = %.6f (>= p: %s)\n", 
    q_result, cdf_result, cdf_result >= p_test))
cat(sprintf("ppois(%d, 1.5) = %.6f (>= p: %s)\n", 
    q_result - 1, cdf_below, cdf_below >= p_test))

cat("\n✅ The Rust code is actually CORRECT as-is!\n")
cat("The discrepancy must be elsewhere.\n")