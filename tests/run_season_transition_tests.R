#!/usr/bin/env Rscript

# Run tests for season transition functionality

library(testthat)

cat("Running Season Transition Tests\n")
cat("==============================\n\n")

# Set working directory to tests folder
setwd(dirname(sys.frame(1)$ofile))

# Source required functions from RCode
source("../scripts/season_transition.R")

# Run specific test files
cat("Testing CLI argument parsing...\n")
test_file("testthat/test-cli-arguments.R")

cat("\nTesting second team conversion...\n")
test_file("testthat/test-second-team-conversion.R")

cat("\nTesting team count validation...\n")
test_file("testthat/test-team-count-validation.R")

cat("\nAll tests completed!\n")