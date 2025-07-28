# Test suite for season processor functionality

library(testthat)
library(mockery)

# Source required files directly - the helper seems to not be working in test context
source("../../RCode/season_processor.R")
source("../../RCode/team_data_carryover.R")

context("Season Processor - Team Data Carryover")

test_that("process_league_teams carries over ShortText from previous season", {
  # Setup: Create mock previous season data
  prev_season_data <- data.frame(
    TeamID = c(168, 167, 165),
    ShortText = c("B04", "HOF", "BVB"),
    Promotion = c(0, 0, 0),
    InitialELO = c(1765, 1628, 1885),
    stringsAsFactors = FALSE
  )
  
  # Mock API response with same teams
  api_teams <- list(
    list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE),
    list(id = 167, name = "Hoffenheim", is_second_team = FALSE),
    list(id = 165, name = "Borussia Dortmund", is_second_team = FALSE)
  )
  
  # Mock final ELOs
  final_elos <- data.frame(
    TeamID = c(168, 167, 165),
    FinalELO = c(1800, 1650, 1900)
  )
  
  # Test
  result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_season_data)
  
  # Extract short names from result
  short_names <- sapply(result, function(t) t$short_name)
  team_ids <- sapply(result, function(t) t$id)
  
  # Assertions
  expect_equal(short_names[team_ids == 168], "B04")
  expect_equal(short_names[team_ids == 167], "HOF")
  expect_equal(short_names[team_ids == 165], "BVB")
})

test_that("process_league_teams generates ShortText only for new teams", {
  # Setup: Previous season has teams 168, 167
  prev_season_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1765, 1628),
    stringsAsFactors = FALSE
  )
  
  # API returns existing teams plus new team 1320
  api_teams <- list(
    list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE),
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)  # New team
  )
  
  final_elos <- data.frame(
    TeamID = c(168),
    FinalELO = c(1800)
  )
  
  # Mock prompt_for_team_info to return FCE for new team
  mock_prompt <- mock(list(short_name = "FCE", initial_elo = 1100, promotion_value = 0))
  stub(process_league_teams, "prompt_for_team_info", mock_prompt)
  
  # Test
  result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_season_data)
  
  # Extract data
  short_names <- sapply(result, function(t) t$short_name)
  team_ids <- sapply(result, function(t) t$id)
  
  # Assertions
  expect_equal(short_names[team_ids == 168], "B04")  # Existing
  expect_equal(short_names[team_ids == 1320], "FCE") # New
  
  # Verify prompt was called only for new team
  expect_called(mock_prompt, 1)
})

test_that("process_league_teams uses final ELO for existing teams", {
  # Setup
  prev_season_data <- data.frame(
    TeamID = c(168),
    ShortText = c("B04"),
    Promotion = c(0),
    InitialELO = c(1765),  # Initial ELO from previous season start
    stringsAsFactors = FALSE
  )
  
  api_teams <- list(
    list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE)
  )
  
  # Final ELO after all matches
  final_elos <- data.frame(
    TeamID = c(168),
    FinalELO = c(1823)  # Different from initial
  )
  
  # Test
  result <- process_league_teams(api_teams, "78", "2025", final_elos, 1100, prev_season_data)
  
  # Assertions
  expect_equal(result[[1]]$initial_elo, 1823)  # Should use final ELO, not 1765
})

context("Season Processor - ELO Baseline Passing")

test_that("Liga3 baseline is passed to prompt_for_team_info", {
  # Setup
  api_teams <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)
  )
  
  final_elos <- data.frame(TeamID = numeric(), FinalELO = numeric())
  
  # Mock prompt function to capture baseline
  captured_baseline <- NULL
  mock_prompt <- mock(
    list(short_name = "FCE", initial_elo = 1234, promotion_value = 0),
    cycle = TRUE
  )
  
  stub(process_league_teams, "prompt_for_team_info", function(name, league, existing, baseline) {
    captured_baseline <<- baseline
    mock_prompt()
  })
  
  # Test with baseline 1234
  process_league_teams(api_teams, "80", "2025", final_elos, 1234, NULL)
  
  # Assertions
  expect_equal(captured_baseline, 1234)
})

context("Season Processor - Season Validation")

test_that("process_single_season validates previous season completion", {
  # Mock validation to return FALSE
  stub(process_single_season, "validate_season_completion", FALSE)
  
  # Test - process_single_season returns a list with success = FALSE on error
  result <- process_single_season("2025", "2024")
  
  expect_false(result$success)
  expect_equal(result$error, "Season 2024 not finished, no season transition possible.")
})

context("Team Data Carryover Module")

test_that("load_previous_team_list loads valid team data", {
  # Create temporary test file
  test_dir <- tempdir()
  test_file <- file.path(test_dir, "RCode", "TeamList_2024.csv")
  dir.create(file.path(test_dir, "RCode"), recursive = TRUE, showWarnings = FALSE)
  
  # Write test data
  test_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1765, 1628)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock file path
  stub(load_previous_team_list, "paste0", function(...) test_file)
  stub(load_previous_team_list, "safe_file_read", function(path, ...) test_data)
  
  # Test
  result <- load_previous_team_list("2024")
  
  # Assertions
  expect_equal(nrow(result), 2)
  expect_equal(result$ShortText[1], "B04")
  
  # Cleanup
  unlink(file.path(test_dir, "RCode"), recursive = TRUE)
})

test_that("get_existing_team_data returns correct team info", {
  # Setup
  prev_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, -50),
    stringsAsFactors = FALSE
  )
  
  # Test existing team
  result <- get_existing_team_data(168, prev_data)
  expect_equal(result$short_name, "B04")
  expect_equal(result$promotion_value, 0)
  
  # Test second team
  result <- get_existing_team_data(167, prev_data)
  expect_equal(result$short_name, "HOF")
  expect_equal(result$promotion_value, -50)
  
  # Test non-existing team
  result <- get_existing_team_data(999, prev_data)
  expect_null(result)
})

test_that("validate_short_name_uniqueness detects duplicates", {
  # Test with duplicates
  short_names <- c("B04", "HOF", "B04", "BVB")
  result <- validate_short_name_uniqueness(short_names)
  
  expect_false(result$valid)
  expect_true("B04" %in% result$duplicates)
  expect_equal(length(result$duplicates), 1)
  
  # Test without duplicates
  short_names <- c("B04", "HOF", "BVB", "FCB")
  result <- validate_short_name_uniqueness(short_names)
  
  expect_true(result$valid)
})

test_that("ensure_unique_short_names fixes duplicates", {
  # Setup teams with duplicate short names
  teams <- list(
    list(id = 168, short_name = "B04"),
    list(id = 167, short_name = "B04"),  # Duplicate
    list(id = 165, short_name = "BVB")
  )
  
  # Test
  result <- ensure_unique_short_names(teams)
  
  # Extract short names
  short_names <- sapply(result, function(t) t$short_name)
  
  # Assertions
  expect_equal(short_names[1], "B04")  # First keeps original
  expect_match(short_names[2], "B0[0-9]")  # Second gets modified
  expect_equal(short_names[3], "BVB")  # Unaffected
  expect_equal(length(unique(short_names)), 3)  # All unique
})