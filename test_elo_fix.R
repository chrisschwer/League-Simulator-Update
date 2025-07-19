#!/usr/bin/env Rscript

# Test script to verify ELO calculation fix
# This tests that fetch_league_results returns the correct data
# and that ELO calculations work properly

library(httr)
library(jsonlite)

# Color output
green <- function(text) paste0("\033[32m", text, "\033[0m")
red <- function(text) paste0("\033[31m", text, "\033[0m")
yellow <- function(text) paste0("\033[33m", text, "\033[0m")
blue <- function(text) paste0("\033[34m", text, "\033[0m")

cat(blue("=== ELO Calculation Fix Test ===\n\n"))

# Source required functions
cat("Loading ELO aggregation functions...\n")
source("RCode/elo_aggregation.R")

# Test 1: Verify fetch_league_results works
cat(yellow("\n1. Testing fetch_league_results\n"))
cat("Fetching Bundesliga 2023 finished matches...\n")

tryCatch({
  matches <- fetch_league_results("78", "2023")
  
  if (!is.null(matches) && nrow(matches) > 0) {
    cat(green("✓ Successfully fetched"), nrow(matches), "matches\n")
    
    # Check data structure
    expected_cols <- c("fixture_date", "teams_home_id", "teams_away_id", 
                      "goals_home", "goals_away", "fixture_status_short")
    missing_cols <- setdiff(expected_cols, names(matches))
    
    if (length(missing_cols) == 0) {
      cat(green("✓ All required columns present\n"))
    } else {
      cat(red("✗ Missing columns:"), paste(missing_cols, collapse = ", "), "\n")
    }
    
    # Show sample matches
    cat("\nSample matches:\n")
    sample_matches <- head(matches, 5)
    for (i in 1:nrow(sample_matches)) {
      m <- sample_matches[i,]
      cat(sprintf("  Match %d: Team %s vs %s: %d-%d\n", 
                  i, m$teams_home_id, m$teams_away_id, 
                  m$goals_home, m$goals_away))
    }
    
    # Verify all are finished
    non_ft <- sum(matches$fixture_status_short != "FT")
    if (non_ft == 0) {
      cat(green("✓ All matches have status 'FT' (finished)\n"))
    } else {
      cat(red("✗"), non_ft, "matches don't have FT status\n")
    }
    
  } else {
    cat(red("✗ No matches returned\n"))
  }
  
}, error = function(e) {
  cat(red("✗ Error:"), e$message, "\n")
})

# Test 2: Test get_league_matches (the wrapper function)
cat(yellow("\n2. Testing get_league_matches\n"))

tryCatch({
  league_matches <- get_league_matches("78", "2023")
  
  if (!is.null(league_matches) && nrow(league_matches) > 0) {
    cat(green("✓ get_league_matches returned"), nrow(league_matches), "matches\n")
    
    # This should have filtered for FT only and have the right columns
    expected_cols <- c("fixture_date", "teams_home_id", "teams_away_id", 
                      "goals_home", "goals_away")
    missing_cols <- setdiff(expected_cols, names(league_matches))
    
    if (length(missing_cols) == 0) {
      cat(green("✓ Data structure correct for ELO calculation\n"))
    } else {
      cat(red("✗ Missing columns:"), paste(missing_cols, collapse = ", "), "\n")
    }
  } else {
    cat(red("✗ No matches returned from get_league_matches\n"))
  }
  
}, error = function(e) {
  cat(red("✗ Error:"), e$message, "\n")
})

# Test 3: Test ELO calculation for a specific team
cat(yellow("\n3. Testing ELO Calculation for Bayer Leverkusen (B04)\n"))

tryCatch({
  # Get all matches for the season
  all_matches <- get_league_matches("78", "2023")
  
  if (!is.null(all_matches) && nrow(all_matches) > 0) {
    # Filter for B04 matches (TeamID 168)
    b04_matches <- all_matches[all_matches$teams_home_id == "168" | 
                               all_matches$teams_away_id == "168", ]
    
    cat("Found", nrow(b04_matches), "matches involving B04\n")
    
    if (nrow(b04_matches) > 0) {
      # Count wins, draws, losses
      wins <- 0
      draws <- 0
      losses <- 0
      
      for (i in 1:nrow(b04_matches)) {
        match <- b04_matches[i,]
        if (match$teams_home_id == "168") {
          # B04 is home
          if (match$goals_home > match$goals_away) wins <- wins + 1
          else if (match$goals_home == match$goals_away) draws <- draws + 1
          else losses <- losses + 1
        } else {
          # B04 is away
          if (match$goals_away > match$goals_home) wins <- wins + 1
          else if (match$goals_away == match$goals_home) draws <- draws + 1
          else losses <- losses + 1
        }
      }
      
      cat("Results: ", wins, "W ", draws, "D ", losses, "L\n")
      cat("Win rate: ", round(wins/nrow(b04_matches)*100, 1), "%\n")
      
      # Show first few matches
      cat("\nFirst 5 matches:\n")
      for (i in 1:min(5, nrow(b04_matches))) {
        match <- b04_matches[i,]
        date <- substr(match$fixture_date, 1, 10)
        if (match$teams_home_id == "168") {
          cat(sprintf("  %s: B04 %d-%d Team_%s (Home)\n", 
                      date, match$goals_home, match$goals_away, match$teams_away_id))
        } else {
          cat(sprintf("  %s: Team_%s %d-%d B04 (Away)\n", 
                      date, match$teams_home_id, match$goals_home, match$goals_away))
        }
      }
    }
  }
  
}, error = function(e) {
  cat(red("✗ Error:"), e$message, "\n")
})

# Test 4: Simulate ELO calculation
cat(yellow("\n4. Testing Full ELO Calculation\n"))

tryCatch({
  cat("Running calculate_final_elos for 2023 season...\n")
  
  # This will use the actual team list and calculate ELOs
  final_elos <- calculate_final_elos("2023")
  
  if (!is.null(final_elos) && nrow(final_elos) > 0) {
    cat(green("✓ ELO calculation completed for"), nrow(final_elos), "teams\n")
    
    # Find B04's ELO
    b04_row <- final_elos[final_elos$TeamID == "168", ]
    if (nrow(b04_row) > 0) {
      cat("\nB04 Final ELO:", round(b04_row$FinalELO[1], 2), "\n")
      cat("(Started at 1765 according to TeamList_2023.csv)\n")
    }
    
    # Show top 5 teams by ELO
    cat("\nTop 5 teams by final ELO:\n")
    top_teams <- head(final_elos[order(final_elos$FinalELO, decreasing = TRUE), ], 5)
    for (i in 1:nrow(top_teams)) {
      cat(sprintf("  %d. Team %s: %.2f\n", i, top_teams$TeamID[i], top_teams$FinalELO[i]))
    }
  } else {
    cat(red("✗ ELO calculation returned no data\n"))
  }
  
}, error = function(e) {
  cat(red("✗ Error in ELO calculation:"), e$message, "\n")
})

cat(blue("\n=== Test Complete ===\n"))
cat("\nIf all tests passed, you can now run season transition and ELO values should update correctly!\n")
cat("Command: Rscript scripts/season_transition.R 2023 2024 --non-interactive\n")