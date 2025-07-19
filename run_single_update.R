#!/usr/bin/env Rscript

# Script to run a single update for season 2025
# This will generate initial prognoses and update the Shiny app

cat("=== Running Single Update for Season 2025 ===\n\n")

# Set working directory to project root
setwd(dirname(dirname(rstudioapi::getSourceEditorContext()$path)))

# Source the update function
source("RCode/update_all_leagues_loop.R")

# Run a single update (loops = 1)
cat("Starting simulation for season 2025...\n")
cat("This will:\n")
cat("  1. Fetch current fixtures from API\n")
cat("  2. Run 10,000 simulations for each league\n")
cat("  3. Update the Shiny app with results\n\n")

# Run with:
# - duration = 480 (not used when loops = 1)
# - loops = 1 (single run)
# - initial_wait = 0 (no wait)
# - n = 10000 (number of simulations)
# - saison = "2025"
# - TeamList_file = path to 2025 team list

update_all_leagues_loop(
  duration = 480,
  loops = 1,
  initial_wait = 0,
  n = 10000,
  saison = "2025",
  TeamList_file = "RCode/TeamList_2025.csv"
)

cat("\n=== Update Complete ===\n")
cat("Check the Shiny app for the updated prognoses!\n")