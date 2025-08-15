#!/usr/bin/env Rscript

# Single match simulation comparison: R/C++ vs Rust
# Test with fixed random values to isolate discrepancies

cat("=== Single Match Simulation Test ===\n\n")

# Load R/C++ functions
library(Rcpp)
sourceCpp("RCode/SpielNichtSimulieren.cpp")
source("RCode/SpielCPP.R")

# Test parameters
elo_home <- 1452.232  # ELV's actual ELO
elo_away <- 1500.000  # Example opponent
random_home <- 0.5
random_away <- 0.5
mod_factor <- 20
home_advantage <- 65
tore_slope <- 0.0017854953143549
tore_intercept <- 1.3218390804597700

cat("Test Parameters:\n")
cat(sprintf("  ELO Home: %.3f (like ELV)\n", elo_home))
cat(sprintf("  ELO Away: %.3f\n", elo_away))
cat(sprintf("  Random values: %.1f, %.1f\n", random_home, random_away))
cat(sprintf("  Mod factor: %.0f\n", mod_factor))
cat(sprintf("  Home advantage: %.0f\n", home_advantage))
cat(sprintf("  ToreSlope: %.10f\n", tore_slope))
cat(sprintf("  ToreIntercept: %.10f\n\n", tore_intercept))

# Calculate expected goals (what both R and Rust should compute)
cat("=== Goal Generation Calculation ===\n")
elo_delta <- elo_home + home_advantage - elo_away
cat(sprintf("ELO delta: %.3f + %.0f - %.3f = %.3f\n", 
    elo_home, home_advantage, elo_away, elo_delta))

tore_heim_durchschnitt <- max(elo_delta * tore_slope + tore_intercept, 0.001)
tore_gast_durchschnitt <- max((-elo_delta) * tore_slope + tore_intercept, 0.001)

cat(sprintf("Expected goals home: %.3f * %.10f + %.10f = %.6f\n", 
    elo_delta, tore_slope, tore_intercept, tore_heim_durchschnitt))
cat(sprintf("Expected goals away: %.3f * %.10f + %.10f = %.6f\n", 
    -elo_delta, tore_slope, tore_intercept, tore_gast_durchschnitt))

# Generate goals using R's qpois
goals_home_r <- qpois(p = random_home, lambda = tore_heim_durchschnitt)
goals_away_r <- qpois(p = random_away, lambda = tore_gast_durchschnitt)

cat(sprintf("\nR's qpois results:\n"))
cat(sprintf("  Goals home: qpois(%.1f, %.6f) = %d\n", 
    random_home, tore_heim_durchschnitt, goals_home_r))
cat(sprintf("  Goals away: qpois(%.1f, %.6f) = %d\n", 
    random_away, tore_gast_durchschnitt, goals_away_r))

# Now run full SpielCPP simulation
cat("\n=== Full R/C++ Simulation ===\n")
result_r <- SpielCPP(
  ELOHeim = elo_home,
  ELOGast = elo_away,
  ZufallHeim = random_home,
  ZufallGast = random_away,
  ModFaktor = mod_factor,
  Heimvorteil = home_advantage,
  Simulieren = TRUE,
  ToreSlope = tore_slope,
  ToreIntercept = tore_intercept
)

cat(sprintf("Match result: %d - %d\n", result_r[3], result_r[4]))
cat(sprintf("New ELO Home: %.3f (change: %+.3f)\n", 
    result_r[1], result_r[1] - elo_home))
cat(sprintf("New ELO Away: %.3f (change: %+.3f)\n", 
    result_r[2], result_r[2] - elo_away))
cat(sprintf("Win probability (home): %.3f\n", result_r[5]))

# Test multiple random values to see pattern
cat("\n=== Testing Multiple Random Values ===\n")
test_randoms <- list(
  c(0.1, 0.1),
  c(0.3, 0.3),
  c(0.5, 0.5),
  c(0.7, 0.7),
  c(0.9, 0.9),
  c(0.2, 0.8),
  c(0.8, 0.2)
)

cat("Random pairs and resulting goals:\n")
for (rands in test_randoms) {
  goals_h <- qpois(rands[1], tore_heim_durchschnitt)
  goals_a <- qpois(rands[2], tore_gast_durchschnitt)
  cat(sprintf("  (%.1f, %.1f) → %d - %d\n", 
      rands[1], rands[2], goals_h, goals_a))
}

# Now create test data for Rust comparison
cat("\n=== Preparing Rust Comparison ===\n")
cat("To compare with Rust, run the following:\n")
cat("1. Start Rust API: cd league-simulator-rust && cargo run\n")
cat("2. Run: Rscript tests/compare_single_match_rust.R\n")

# Save test cases for Rust comparison
test_data <- data.frame(
  random_home = sapply(test_randoms, `[`, 1),
  random_away = sapply(test_randoms, `[`, 2),
  elo_home = elo_home,
  elo_away = elo_away,
  mod_factor = mod_factor,
  home_advantage = home_advantage,
  tore_slope = tore_slope,
  tore_intercept = tore_intercept
)

write.csv(test_data, "single_match_test_cases.csv", row.names = FALSE)
cat("\nTest cases saved to single_match_test_cases.csv\n")

cat("\n✅ Single match test complete!\n")