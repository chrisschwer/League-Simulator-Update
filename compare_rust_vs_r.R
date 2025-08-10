#!/usr/bin/env Rscript

# Script to compare Rust and R simulation outputs for validation

library(jsonlite)
library(Rcpp)

# Source R implementations
sourceCpp("RCode/SpielNichtSimulieren.cpp")
source("RCode/leagueSimulatorCPP.R")
source("RCode/simulationsCPP.R")
source("RCode/SaisonSimulierenCPP.R")
source("RCode/SpielCPP.R")
source("RCode/Tabelle.R")

# Function to run R simulation and save results
run_r_simulation <- function(n = 100) {
  cat("Running R simulation with", n, "iterations...\n")
  
  # Create test season data
  season <- data.frame(
    TeamHeim = c(1, 2, 3, 1, 2, 3),
    TeamGast = c(2, 3, 1, 3, 1, 2),
    ToreHeim = c(2, 1, NA, NA, NA, NA),
    ToreGast = c(1, 1, NA, NA, NA, NA)
  )
  
  # Add team ELO columns
  season$Team1 <- 1500
  season$Team2 <- 1600
  season$Team3 <- 1400
  
  start_time <- Sys.time()
  
  # Run simulation
  result <- leagueSimulatorCPP(season, n = n)
  
  end_time <- Sys.time()
  duration <- as.numeric(end_time - start_time, units = "secs")
  
  list(
    probability_matrix = as.matrix(result),
    duration_seconds = duration,
    iterations = n
  )
}

# Compare with Rust output (would be loaded from Rust API or file)
compare_results <- function(r_result, rust_result) {
  cat("\n=== COMPARISON RESULTS ===\n")
  
  # Compare probability matrices
  if (!is.null(rust_result$probability_matrix)) {
    r_matrix <- r_result$probability_matrix
    rust_matrix <- rust_result$probability_matrix
    
    # Calculate differences
    max_diff <- max(abs(r_matrix - rust_matrix))
    mean_diff <- mean(abs(r_matrix - rust_matrix))
    
    cat("Maximum probability difference:", round(max_diff, 6), "\n")
    cat("Mean probability difference:", round(mean_diff, 6), "\n")
    
    if (max_diff < 0.01) {
      cat("✅ Results match within 1% tolerance\n")
    } else {
      cat("⚠️ Results differ by more than 1%\n")
    }
  }
  
  # Compare performance
  cat("\n=== PERFORMANCE ===\n")
  cat("R duration:", round(r_result$duration_seconds, 3), "seconds\n")
  
  if (!is.null(rust_result$duration_seconds)) {
    cat("Rust duration:", round(rust_result$duration_seconds, 3), "seconds\n")
    speedup <- r_result$duration_seconds / rust_result$duration_seconds
    cat("Speedup:", round(speedup, 1), "x faster\n")
  }
}

# Main execution
main <- function() {
  cat("League Simulator: R vs Rust Comparison\n")
  cat("=====================================\n\n")
  
  # Test with different iteration counts
  for (n in c(100, 1000)) {
    cat("\n--- Testing with", n, "iterations ---\n")
    
    # Run R simulation
    r_result <- run_r_simulation(n)
    
    # Save R results for Rust to compare against
    write_json(r_result, paste0("league-simulator-rust/test_data/r_simulation_", n, ".json"),
               auto_unbox = TRUE, pretty = TRUE, digits = 10)
    
    cat("R simulation completed in", round(r_result$duration_seconds, 3), "seconds\n")
    cat("Results saved for Rust comparison\n")
  }
  
  cat("\n✅ Test data generated. Run Rust tests to compare.\n")
}

# Run if executed directly
if (!interactive()) {
  main()
}