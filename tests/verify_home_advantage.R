#!/usr/bin/env Rscript

# Verify home advantage handling in ELO calculations
# Check if home advantage affects match probability but NOT stored ELO values

cat("=== Home Advantage Handling Verification ===\n\n")

# Source the C++ function
library(Rcpp)
sourceCpp("RCode/SpielNichtSimulieren.cpp")

# Test scenario: Equal teams, home wins 2-1
cat("Test Case: Equal teams (1500 ELO each), home wins 2-1\n")
cat("Home advantage: 65 points\n\n")

# Test 1: With home advantage in calculation (as SpielCPP does)
cat("=== Test 1: Home advantage INCLUDED in calculation ===\n")

# This simulates how SpielCPP calls SpielNichtSimulieren
# SpielCPP adds home advantage to ELOHeim before calling
result_with_advantage <- SpielNichtSimulieren(
  ELOHome = 1500,  # Original ELO
  ELOAway = 1500,  # Original ELO  
  GoalsHome = 2,
  GoalsAway = 1,
  modFactor = 20,
  homeAdvantage = 65  # Home advantage passed
)

cat("Input ELOs: Home = 1500, Away = 1500\n")
cat("Match result: 2-1 (home win)\n")
cat(sprintf("Win probability (with advantage): %.3f\n", result_with_advantage[5]))
cat(sprintf("New ELO Home: %.2f (change: %+.2f)\n", 
    result_with_advantage[1], result_with_advantage[1] - 1500))
cat(sprintf("New ELO Away: %.2f (change: %+.2f)\n", 
    result_with_advantage[2], result_with_advantage[2] - 1500))

# Test 2: Without home advantage (hypothetical equal match)
cat("\n=== Test 2: Home advantage EXCLUDED (for comparison) ===\n")

result_no_advantage <- SpielNichtSimulieren(
  ELOHome = 1500,
  ELOAway = 1500,
  GoalsHome = 2,
  GoalsAway = 1,
  modFactor = 20,
  homeAdvantage = 0  # No home advantage
)

cat("Input ELOs: Home = 1500, Away = 1500\n")
cat("Match result: 2-1 (home win)\n")
cat(sprintf("Win probability (no advantage): %.3f\n", result_no_advantage[5]))
cat(sprintf("New ELO Home: %.2f (change: %+.2f)\n", 
    result_no_advantage[1], result_no_advantage[1] - 1500))
cat(sprintf("New ELO Away: %.2f (change: %+.2f)\n", 
    result_no_advantage[2], result_no_advantage[2] - 1500))

# Analysis
cat("\n=== Analysis ===\n")

elo_change_with_adv <- result_with_advantage[1] - 1500
elo_change_no_adv <- result_no_advantage[1] - 1500

cat(sprintf("ELO change difference: %.2f vs %.2f\n", 
    elo_change_with_adv, elo_change_no_adv))

if (abs(elo_change_with_adv) < abs(elo_change_no_adv)) {
  cat("✅ CORRECT: Home team gains LESS ELO when home advantage is considered\n")
  cat("   (Because the win was more expected with home advantage)\n")
} else {
  cat("⚠️  UNEXPECTED: ELO changes don't follow expected pattern\n")
}

# Test 3: Check what happens in an upset
cat("\n=== Test 3: Away team wins (upset) ===\n")

result_upset <- SpielNichtSimulieren(
  ELOHome = 1500,
  ELOAway = 1500,
  GoalsHome = 1,
  GoalsAway = 2,
  modFactor = 20,
  homeAdvantage = 65
)

cat("Input ELOs: Home = 1500, Away = 1500\n")
cat("Match result: 1-2 (away win - upset with home advantage)\n")
cat(sprintf("Win probability home (with advantage): %.3f\n", result_upset[5]))
cat(sprintf("New ELO Home: %.2f (change: %+.2f)\n", 
    result_upset[1], result_upset[1] - 1500))
cat(sprintf("New ELO Away: %.2f (change: %+.2f)\n", 
    result_upset[2], result_upset[2] - 1500))

# Key insight
cat("\n=== KEY INSIGHT ===\n")
cat("The returned ELO values should be clean (without home advantage baked in).\n")
cat("Home advantage should only affect:\n")
cat("  1. Win probability calculation\n")
cat("  2. The magnitude of ELO change (via expected vs actual result)\n")
cat("But NOT the base ELO values stored for future matches.\n")

# Check ELO conservation
cat("\n=== ELO Conservation Check ===\n")
for (test_name in c("with_advantage", "no_advantage", "upset")) {
  result <- get(paste0("result_", test_name))
  total_before <- 1500 + 1500
  total_after <- result[1] + result[2]
  cat(sprintf("%s: Total ELO before = %.0f, after = %.2f (diff = %.6f)\n",
      test_name, total_before, total_after, total_after - total_before))
}

cat("\n✅ Home advantage verification complete!\n")