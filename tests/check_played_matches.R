#!/usr/bin/env Rscript

# Check how played vs unplayed matches are handled
# This might be where the discrepancy comes from

cat("=== Played vs Unplayed Match Handling ===\n\n")

# In our BL2 test case:
# - 306 total matches
# - 18 played
# - 288 unplayed

cat("BL2 Season Status:\n")
cat("  Total matches: 306\n")
cat("  Played: 18 (5.9%)\n")
cat("  Unplayed: 288 (94.1%)\n\n")

# The R/C++ code (simulationsCPP.R) does this:
cat("R/C++ Approach (from simulationsCPP.R):\n")
cat("1. Separates played and unplayed matches\n")
cat("2. For played matches:\n")
cat("   - Updates ELO values based on actual results\n")
cat("   - Calculates current table with adjustments\n")
cat("   - Extracts new adjustments from current standings\n")
cat("3. For unplayed matches:\n")
cat("   - Simulates using updated ELOs and adjustments\n")
cat("   - Combines with played match results\n\n")

# Critical question: Does Rust do the same?
cat("Critical Questions for Rust:\n")
cat("1. Does it update ELOs for played matches first?\n")
cat("2. Does it carry forward table adjustments?\n")
cat("3. Does it combine played and simulated results correctly?\n\n")

# Let's test with a simple example
cat("=== Test Case: Impact of Played Matches ===\n\n")

library(Rcpp)
sourceCpp("RCode/SpielNichtSimulieren.cpp")

# Two teams, one match played
initial_elo_home <- 1500
initial_elo_away <- 1500
goals_home <- 3
goals_away <- 0

# Calculate ELO update from played match
result <- SpielNichtSimulieren(
  ELOHome = initial_elo_home,
  ELOAway = initial_elo_away,
  GoalsHome = goals_home,
  GoalsAway = goals_away,
  modFactor = 20,
  homeAdvantage = 65
)

new_elo_home <- result[1]
new_elo_away <- result[2]

cat("After played match (3-0 home win):\n")
cat(sprintf("  Home ELO: %.0f → %.0f (change: %+.0f)\n", 
    initial_elo_home, new_elo_home, new_elo_home - initial_elo_home))
cat(sprintf("  Away ELO: %.0f → %.0f (change: %+.0f)\n", 
    initial_elo_away, new_elo_away, new_elo_away - initial_elo_away))

cat("\nImpact on future simulations:\n")
cat("  - Home team now stronger in remaining matches\n")
cat("  - Away team now weaker in remaining matches\n")
cat("  - This affects ALL subsequent Monte Carlo iterations\n\n")

# For ELV in BL2:
cat("=== ELV Specific Analysis ===\n\n")

# ELV's played matches would affect their ELO
# If Rust doesn't handle this correctly, it could explain the discrepancy

cat("Hypothesis: Rust might be:\n")
cat("1. Not updating ELOs from played matches\n")
cat("2. Using original ELOs for all simulations\n")
cat("3. This would make ELV appear weaker than they should be\n")
cat("4. Result: Lower promotion probability (13.9% vs 17.6%)\n\n")

cat("To verify, we need to check:\n")
cat("1. How Rust processes the 18 played BL2 matches\n")
cat("2. What ELO values it uses for simulations\n")
cat("3. Whether adjustments are carried forward\n\n")

cat("✅ Analysis complete!\n")
cat("\nNext step: Examine Rust's season simulation code\n")
cat("File: league-simulator-rust/src/simulation/season.rs\n")