# Test suite for ELO aggregation functionality
# Tests the fixes for Liga3 baseline calculation and ELO carryover issues

library(testthat)
library(mockery)

# Source required files
tryCatch({
  source("../../RCode/elo_aggregation.R")
  source("../../RCode/SpielCPP.R")
}, error = function(e) {
  warning("Could not source files, assuming functions are already loaded")
})

context("ELO Aggregation - Liga3 Baseline Calculation")

test_that("calculate_liga3_relegation_baseline returns different values for different seasons", {
  # Mock get_league_matches to return different Liga3 teams for different seasons
  mock_matches_2023 <- data.frame(
    fixture_date = c("2023-05-01", "2023-05-08", "2023-05-15"),
    teams_home_id = c(1001, 1002, 1003),
    teams_away_id = c(1004, 1005, 1006),
    goals_home = c(1, 2, 0),
    goals_away = c(1, 1, 2),
    fixture_status_short = c("FT", "FT", "FT"),
    stringsAsFactors = FALSE
  )
  
  mock_matches_2024 <- data.frame(
    fixture_date = c("2024-05-01", "2024-05-08", "2024-05-15"),
    teams_home_id = c(2001, 2002, 2003),  # Different teams
    teams_away_id = c(2004, 2005, 2006),
    goals_home = c(0, 1, 3),
    goals_away = c(2, 0, 1),
    fixture_status_short = c("FT", "FT", "FT"),
    stringsAsFactors = FALSE
  )
  
  # Mock calculate_final_elos to return different ELO distributions
  mock_final_elos_2023 <- data.frame(
    TeamID = c(1001, 1002, 1003, 1004, 1005, 1006),
    FinalELO = c(1200, 1150, 1100, 1050, 1000, 950)  # Lowest 4: 950, 1000, 1050, 1100
  )
  
  mock_final_elos_2024 <- data.frame(
    TeamID = c(2001, 2002, 2003, 2004, 2005, 2006),
    FinalELO = c(1300, 1250, 1200, 1150, 1100, 1050)  # Lowest 4: 1050, 1100, 1150, 1200
  )
  
  # Create mock functions
  mock_get_matches <- function(league, season) {
    if (season == "2023") return(mock_matches_2023)
    if (season == "2024") return(mock_matches_2024)
    return(NULL)
  }
  
  mock_calculate_elos <- function(season) {
    if (season == "2023") return(mock_final_elos_2023)
    if (season == "2024") return(mock_final_elos_2024)
    return(NULL)
  }
  
  # Stub the functions
  stub(calculate_liga3_relegation_baseline, "get_league_matches", mock_get_matches)
  stub(calculate_liga3_relegation_baseline, "calculate_final_elos", mock_calculate_elos)
  
  # Test
  baseline_2023 <- calculate_liga3_relegation_baseline("2023")
  baseline_2024 <- calculate_liga3_relegation_baseline("2024")
  
  # Assertions
  expected_2023 <- mean(c(950, 1000, 1050, 1100))  # 1025
  expected_2024 <- mean(c(1050, 1100, 1150, 1200))  # 1125
  
  expect_equal(baseline_2023, expected_2023)
  expect_equal(baseline_2024, expected_2024)
  expect_true(baseline_2024 > baseline_2023)  # Different baselines
})

test_that("calculate_liga3_relegation_baseline falls back to 1046 on error", {
  # Mock to always fail
  stub(calculate_liga3_relegation_baseline, "calculate_final_elos", function(season) {
    stop("Mock API error")
  })
  
  # Test
  result <- calculate_liga3_relegation_baseline("2024")
  
  # Should fall back to default
  expect_equal(result, 1046)
})

test_that("calculate_liga3_relegation_baseline handles insufficient teams", {
  # Mock with only 2 teams (need 4)
  mock_matches <- data.frame(
    teams_home_id = c(1001),
    teams_away_id = c(1002),
    stringsAsFactors = FALSE
  )
  
  mock_final_elos <- data.frame(
    TeamID = c(1001, 1002),
    FinalELO = c(1200, 1100)
  )
  
  stub(calculate_liga3_relegation_baseline, "get_league_matches", function(...) mock_matches)
  stub(calculate_liga3_relegation_baseline, "calculate_final_elos", function(...) mock_final_elos)
  
  # Test
  result <- calculate_liga3_relegation_baseline("2024")
  
  # Should fall back to default
  expect_equal(result, 1046)
})

context("ELO Aggregation - Final ELO Calculation")

test_that("calculate_final_elos uses temporary files when regular file doesn't exist", {
  # Create mock temporary files
  temp_dir <- tempdir()
  temp_file1 <- file.path(temp_dir, "TeamList_2024_League78_temp.csv")
  temp_file2 <- file.path(temp_dir, "TeamList_2024_League79_temp.csv")
  
  # Create temp data
  temp_data1 <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1765, 1628),
    stringsAsFactors = FALSE
  )
  
  temp_data2 <- data.frame(
    TeamID = c(165, 164),
    ShortText = c("BVB", "M05"),
    Promotion = c(0, 0),
    InitialELO = c(1885, 1656),
    stringsAsFactors = FALSE
  )
  
  write.table(temp_data1, temp_file1, sep = ";", row.names = FALSE, quote = FALSE)
  write.table(temp_data2, temp_file2, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock list.files to find our temp files
  stub(calculate_final_elos, "list.files", function(path, pattern, ...) {
    if (grepl("TeamList_2024_League.*_temp", pattern)) {
      return(c(temp_file1, temp_file2))
    }
    return(character(0))
  })
  
  # Mock file.exists to say regular file doesn't exist
  stub(calculate_final_elos, "file.exists", function(path) {
    !grepl("TeamList_2024.csv", path)
  })
  
  # Mock get_league_matches to return no matches (simplified test)
  stub(calculate_final_elos, "get_league_matches", function(...) NULL)
  
  # Test
  result <- calculate_final_elos("2024")
  
  # Should have combined data from both temp files
  expect_equal(nrow(result), 4)
  expect_true(all(c(168, 167, 165, 164) %in% result$TeamID))
  expect_true(all(c(1765, 1628, 1885, 1656) %in% result$FinalELO))
  
  # Cleanup
  unlink(c(temp_file1, temp_file2))
})

test_that("calculate_final_elos processes matches and updates ELOs", {
  # Mock team data
  team_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1500, 1500),  # Start equal
    stringsAsFactors = FALSE
  )
  
  # Mock match data - B04 wins against HOF
  mock_matches <- data.frame(
    fixture_date = c("2024-03-01"),
    teams_home_id = c(168),  # B04
    teams_away_id = c(167),  # HOF
    goals_home = c(2),
    goals_away = c(1),
    fixture_status_short = c("FT"),
    stringsAsFactors = FALSE
  )
  
  # Mock file operations
  stub(calculate_final_elos, "file.exists", function(...) TRUE)
  stub(calculate_final_elos, "read.csv", function(...) team_data)
  stub(calculate_final_elos, "list.files", function(...) character(0))  # No temp files
  
  # Mock get_league_matches
  stub(calculate_final_elos, "get_league_matches", function(league, season) {
    if (league %in% c("78", "79", "80")) return(mock_matches)
    return(NULL)
  })
  
  # Mock SpielCPP to simulate ELO change
  stub(calculate_final_elos, "exists", function(name) name == "SpielNichtSimulieren")
  stub(calculate_final_elos, "SpielNichtSimulieren", function(home_elo, away_elo, goals_home, goals_away, mod, home_adv) {
    # B04 wins, so ELO increases for home, decreases for away
    return(c(home_elo + 20, away_elo - 20))
  })
  
  # Test
  result <- calculate_final_elos("2024")
  
  # Assertions
  expect_equal(nrow(result), 2)
  
  # B04 should have higher ELO after winning
  b04_final <- result$FinalELO[result$TeamID == 168]
  hof_final <- result$FinalELO[result$TeamID == 167]
  
  expect_true(b04_final > 1500)  # B04 ELO increased
  expect_true(hof_final < 1500)  # HOF ELO decreased
  expect_true(b04_final > hof_final)  # B04 > HOF
})

context("ELO Aggregation - Match Processing")

test_that("update_elos_for_match handles missing teams gracefully", {
  # Setup ELO data
  current_elos <- data.frame(
    TeamID = c(168, 167),
    CurrentELO = c(1500, 1500),
    stringsAsFactors = FALSE
  )
  
  # Match with unknown team
  match <- list(
    teams_home_id = 999,  # Unknown team
    teams_away_id = 167,  # Known team
    goals_home = 2,
    goals_away = 1
  )
  
  # Test
  result <- update_elos_for_match(current_elos, match)
  
  # Should return original ELOs unchanged
  expect_equal(result, current_elos)
})

test_that("update_elos_for_match uses SpielNichtSimulieren when available", {
  # Setup
  current_elos <- data.frame(
    TeamID = c(168, 167),
    CurrentELO = c(1500, 1600),
    stringsAsFactors = FALSE
  )
  
  match <- list(
    teams_home_id = 168,
    teams_away_id = 167,
    goals_home = 3,
    goals_away = 1
  )
  
  # Mock SpielNichtSimulieren
  stub(update_elos_for_match, "exists", function(name) name == "SpielNichtSimulieren")
  stub(update_elos_for_match, "SpielNichtSimulieren", function(home_elo, away_elo, goals_home, goals_away, mod, home_adv) {
    return(c(home_elo + 25, away_elo - 25))
  })
  
  # Test
  result <- update_elos_for_match(current_elos, match)
  
  # Check ELO changes
  expect_equal(result$CurrentELO[result$TeamID == 168], 1525)
  expect_equal(result$CurrentELO[result$TeamID == 167], 1575)
})

context("ELO Aggregation - Integration with Temporary Files")

test_that("Liga3 baseline calculation works with temporary files", {
  # This test ensures the fix for circular dependency works
  # Create temporary team files
  temp_dir <- tempdir()
  temp_file <- file.path(temp_dir, "TeamList_2024_League80_temp.csv")
  
  # Liga3 teams with varying ELOs - need enough for standings
  liga3_teams <- data.frame(
    TeamID = c(1001, 1002, 1003, 1004, 1005, 1006),
    ShortText = c("COT", "AAC", "HAV", "HO2", "ST2", "MSV"),
    Promotion = c(0, 0, 0, -50, -50, 0),
    InitialELO = c(1200, 1150, 1100, 1050, 1000, 950),
    stringsAsFactors = FALSE
  )
  
  write.table(liga3_teams, temp_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock Liga3 matches - comprehensive schedule to establish standings
  liga3_matches <- data.frame(
    fixture_date = c("2024-04-01", "2024-04-08", "2024-04-15", 
                     "2024-04-22", "2024-04-29", "2024-05-06",
                     "2024-05-13", "2024-05-20", "2024-05-27"),
    teams_home_id = c(1001, 1002, 1003, 1004, 1005, 1006,
                      1001, 1002, 1003),
    teams_away_id = c(1002, 1003, 1004, 1005, 1006, 1001,
                      1003, 1004, 1005),
    goals_home = c(3, 2, 1, 0, 0, 1,    # First round results
                   4, 3, 0),             # Second round partial
    goals_away = c(0, 1, 1, 2, 3, 0,
                   0, 1, 2),
    fixture_status_short = rep("FT", 9),
    stringsAsFactors = FALSE
  )
  
  # Mock functions for calculate_final_elos to use temp files
  stub(calculate_liga3_relegation_baseline, "calculate_final_elos", function(season) {
    # Return final ELOs after season - teams that lost more have lower ELOs
    return(data.frame(
      TeamID = c(1001, 1002, 1003, 1004, 1005, 1006),
      FinalELO = c(1280, 1200, 1080, 1000, 920, 970),  # Based on performance
      stringsAsFactors = FALSE
    ))
  })
  
  stub(calculate_liga3_relegation_baseline, "get_league_matches", function(...) liga3_matches)
  
  # Mock Tabelle to return standings based on match results
  stub(calculate_liga3_relegation_baseline, "Tabelle", function(season, numberTeams, numberGames) {
    # Based on match results, teams finish in this order
    return(matrix(c(
      1, 1, 12, 1, 11, 15,  # Team 1001 - 1st place (won most)
      2, 2, 8, 4, 4, 9,     # Team 1002 - 2nd place
      3, 3, 5, 7, -2, 6,    # Team 1003 - 3rd place (relegated)
      4, 4, 4, 8, -4, 3,    # Team 1006 - 4th place (relegated)
      5, 5, 3, 9, -6, 3,    # Team 1004 - 5th place (relegated)
      6, 6, 2, 11, -9, 0    # Team 1005 - 6th place (relegated)
    ), ncol = 6, byrow = TRUE))
  })
  
  # Mock file operations
  stub(calculate_liga3_relegation_baseline, "file.exists", function(path) {
    if (grepl("temp\\.csv$", path)) return(TRUE)  # Temp file exists
    return(FALSE)  # No other files
  })
  
  stub(calculate_liga3_relegation_baseline, "list.files", function(path, pattern, ...) {
    if (grepl("temp", pattern)) return(temp_file)
    return(character(0))
  })
  
  # Test
  baseline <- calculate_liga3_relegation_baseline("2024")
  
  # Should calculate from relegated teams (positions 3-6): 1003, 1006, 1004, 1005
  # Their final ELOs are: 1080, 970, 1000, 920
  expected_baseline <- mean(c(1080, 970, 1000, 920))  # 992.5
  expect_equal(baseline, expected_baseline)
  
  # Cleanup
  unlink(temp_file)
})

test_that("ELO aggregation handles mixed file scenarios", {
  # Test when some leagues have temp files and others don't
  temp_dir <- tempdir()
  
  # Only Liga3 has temp file
  temp_file_80 <- file.path(temp_dir, "TeamList_2024_League80_temp.csv")
  liga3_data <- data.frame(
    TeamID = c(1001, 1002),
    ShortText = c("COT", "AAC"),
    Promotion = c(0, 0),
    InitialELO = c(1100, 1050),
    stringsAsFactors = FALSE
  )
  write.table(liga3_data, temp_file_80, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock regular file for other leagues
  regular_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1765, 1628),
    stringsAsFactors = FALSE
  )
  
  # Mock file operations to simulate mixed scenario
  stub(calculate_final_elos, "list.files", function(path, pattern, ...) {
    if (grepl("TeamList_2024_League.*_temp", pattern)) {
      return(temp_file_80)
    }
    return(character(0))
  })
  
  stub(calculate_final_elos, "file.exists", function(path) {
    grepl("TeamList_2024.csv", path)  # Regular file exists
  })
  
  stub(calculate_final_elos, "read.csv", function(path, ...) {
    if (grepl("temp", path)) return(liga3_data)
    return(regular_data)
  })
  
  stub(calculate_final_elos, "get_league_matches", function(...) NULL)  # No matches
  
  # Test - should use temp file data
  result <- calculate_final_elos("2024")
  
  # Should have Liga3 data from temp file, not regular file
  expect_true(all(c(1001, 1002) %in% result$TeamID))
  
  # Cleanup
  unlink(temp_file_80)
})