#!/usr/bin/env Rscript

# Simple test runner that compiles C++ code first

library(Rcpp)

# Compile C++ code
cat("Compiling C++ code...\n")
sourceCpp("RCode/SpielNichtSimulieren.cpp")

# Quick test to verify it works
cat("Testing SpielNichtSimulieren function...\n")
result <- SpielNichtSimulieren(1500, 1500, 2, 1, 40, 100)
cat("Result:", result, "\n")

# Now run the actual tests
cat("\nRunning test suite...\n")
library(testthat)

# Run only the essential tests
test_results <- test_dir("tests/testthat", 
                        filter = "SpielNichtSimulieren|Tabelle|prozent",
                        stop_on_failure = FALSE)

# Summary
cat("\n=== Test Summary ===\n")
cat("Passed:", sum(test_results$passed), "\n")
cat("Failed:", sum(test_results$failed), "\n")
cat("Warnings:", sum(test_results$warning), "\n")