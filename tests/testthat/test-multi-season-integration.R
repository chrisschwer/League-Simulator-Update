# Test suite for multi-season integration
# Tests the complete 2023→2024→2025 workflow that was broken

library(testthat)
library(mockery)

# Functions should be loaded by helper-test-setup.R

context("Multi-Season Integration - Complete Workflow")

test_that("2023→2024→2025 workflow carries over team data correctly", {
  # Setup: Mock the complete multi-season workflow
  
  # 2023 initial data
  teams_2023 <- data.frame(
    TeamID = c(1320, 4259, 1321),
    ShortText = c("FCE", "AAC", "ROS"),
    Promotion = c(0, 0, 0),
    InitialELO = c(1100, 1050, 1200),
    stringsAsFactors = FALSE
  )
  
  # Mock 2024 API response - same teams return
  api_teams_2024 <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE),
    list(id = 4259, name = "Alemannia Aachen", is_second_team = FALSE),
    list(id = 1321, name = "Hansa Rostock", is_second_team = FALSE)
  )
  
  # Mock 2025 API response - same teams return
  api_teams_2025 <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE),
    list(id = 4259, name = "Alemannia Aachen", is_second_team = FALSE),
    list(id = 1321, name = "Hansa Rostock", is_second_team = FALSE)
  )
  
  # Mock 2024 final ELOs after season (different from initial)
  final_elos_2024 <- data.frame(
    TeamID = c(1320, 4259, 1321),
    FinalELO = c(1150, 1080, 1250),  # ELO progression
    stringsAsFactors = FALSE
  )
  
  # Mock 2025 final ELOs
  final_elos_2025 <- data.frame(
    TeamID = c(1320, 4259, 1321),
    FinalELO = c(1200, 1110, 1300),  # Further progression
    stringsAsFactors = FALSE
  )
  
  # Mock functions
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    if (is.null(prev_list)) return(NULL)
    match_row <- prev_list[prev_list$TeamID == team_id, ]
    if (nrow(match_row) == 0) return(NULL)
    return(list(
      short_name = match_row$ShortText[1],
      promotion_value = match_row$Promotion[1]
    ))
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Test 2024 processing
  result_2024 <- process_league_teams(api_teams_2024, "80", "2024", final_elos_2024, 1046, teams_2023)
  
  # Create "previous team list" from 2024 results for 2025 processing
  teams_2024_processed <- data.frame(
    TeamID = sapply(result_2024, function(t) t$id),
    ShortText = sapply(result_2024, function(t) t$short_name),
    Promotion = sapply(result_2024, function(t) t$promotion_value),
    InitialELO = sapply(result_2024, function(t) t$initial_elo),
    stringsAsFactors = FALSE
  )
  
  # Test 2025 processing
  result_2025 <- process_league_teams(api_teams_2025, "80", "2025", final_elos_2025, 1046, teams_2024_processed)
  
  # Assertions for 2024 processing
  expect_length(result_2024, 3)
  
  # Should carry over short names from 2023
  team_1320_2024 <- result_2024[[which(sapply(result_2024, function(t) t$id) == 1320)]]
  team_4259_2024 <- result_2024[[which(sapply(result_2024, function(t) t$id) == 4259)]]
  
  expect_equal(team_1320_2024$short_name, "FCE")
  expect_equal(team_4259_2024$short_name, "AAC")
  
  # Should use final ELO from 2024, not baseline
  expect_equal(team_1320_2024$initial_elo, 1150)
  expect_equal(team_4259_2024$initial_elo, 1080)
  
  # Assertions for 2025 processing
  expect_length(result_2025, 3)
  
  # Should carry over short names from 2024
  team_1320_2025 <- result_2025[[which(sapply(result_2025, function(t) t$id) == 1320)]]
  team_4259_2025 <- result_2025[[which(sapply(result_2025, function(t) t$id) == 4259)]]
  
  expect_equal(team_1320_2025$short_name, "FCE")
  expect_equal(team_4259_2025$short_name, "AAC")
  
  # Should use final ELO from 2025, showing progression
  expect_equal(team_1320_2025$initial_elo, 1200)
  expect_equal(team_4259_2025$initial_elo, 1110)
})

test_that("multi-season processing generates different Liga3 baselines", {
  # Create RCode directory if it doesn't exist
  if (!dir.exists("RCode")) {
    dir.create("RCode", showWarnings = FALSE)
  }
  
  # Create TeamList files that the function expects
  team_list_2023 <- file.path("RCode", "TeamList_2023.csv")
  team_list_2024 <- file.path("RCode", "TeamList_2024.csv")
  
  # Create Liga3 scenarios with different performance levels inline
  # Low scenario for 2023
  liga3_teams_2023 <- c(1320, 4259, 1321, 1001, 1002, 1003, 1004, 1005, 1006, 1007)
  elo_values_2023 <- c(1100, 1050, 1000, 950, 900, 850, 800, 750, 700, 650) # low
  
  liga3_2023 <- list(
    matches = data.frame(
      fixture_date = paste0("2023", "-05-01"),
      teams_home_id = liga3_teams_2023[1:5],
      teams_away_id = liga3_teams_2023[6:10],
      goals_home = c(2, 1, 0, 3, 1),
      goals_away = c(1, 1, 2, 1, 0),
      fixture_status_short = rep("FT", 5),
      stringsAsFactors = FALSE
    ),
    final_elos = data.frame(
      TeamID = liga3_teams_2023,
      FinalELO = elo_values_2023,
      stringsAsFactors = FALSE
    ),
    expected_baseline = mean(sort(elo_values_2023)[1:4])
  )
  
  # High scenario for 2024
  liga3_teams_2024 <- c(1320, 4259, 1321, 1001, 1002, 1003, 1004, 1005, 1006, 1007)
  elo_values_2024 <- c(1350, 1300, 1250, 1200, 1150, 1100, 1050, 1000, 950, 900) # high
  
  liga3_2024 <- list(
    matches = data.frame(
      fixture_date = paste0("2024", "-05-01"),
      teams_home_id = liga3_teams_2024[1:5],
      teams_away_id = liga3_teams_2024[6:10],
      goals_home = c(2, 1, 0, 3, 1),
      goals_away = c(1, 1, 2, 1, 0),
      fixture_status_short = rep("FT", 5),
      stringsAsFactors = FALSE
    ),
    final_elos = data.frame(
      TeamID = liga3_teams_2024,
      FinalELO = elo_values_2024,
      stringsAsFactors = FALSE
    ),
    expected_baseline = mean(sort(elo_values_2024)[1:4])
  )
  
  # Write team list files
  team_data_2023 <- data.frame(
    TeamID = liga3_teams_2023,
    ShortText = c("FCE", "AAC", "HAN", "T01", "T02", "T03", "T04", "T05", "T06", "T07"),
    Promotion = rep(0, 10),
    InitialELO = elo_values_2023,
    stringsAsFactors = FALSE
  )
  
  team_data_2024 <- data.frame(
    TeamID = liga3_teams_2024,
    ShortText = c("FCE", "AAC", "HAN", "T01", "T02", "T03", "T04", "T05", "T06", "T07"),
    Promotion = rep(0, 10),
    InitialELO = elo_values_2024,
    stringsAsFactors = FALSE
  )
  
  write.table(team_data_2023, team_list_2023, sep = ";", row.names = FALSE, quote = FALSE)
  write.table(team_data_2024, team_list_2024, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock functions for Liga3 baseline calculation
  stub(calculate_liga3_relegation_baseline, "get_league_matches", function(league, season) {
    if (season == "2023") return(liga3_2023$matches)
    if (season == "2024") return(liga3_2024$matches)
    return(NULL)
  })
  
  stub(calculate_liga3_relegation_baseline, "calculate_final_elos", function(season) {
    if (season == "2023") return(liga3_2023$final_elos)
    if (season == "2024") return(liga3_2024$final_elos)
    return(NULL)
  })
  
  # Mock the Tabelle function to return league standings
  stub(calculate_liga3_relegation_baseline, "Tabelle", function(season_data, numberTeams, numberGames) {
    # Return mock league table with proper rankings for 10 teams
    # Liga3 teams in our mock: indices 1-10 map to the 10 teams in order
    # For "low" scenario (2023): bottom 4 are teams 7,8,9,10 with ELOs 800,750,700,650
    # For "high" scenario (2024): bottom 4 are teams 7,8,9,10 with ELOs 1050,1000,950,900
    return(matrix(
      c(1, 1, 20, 5, 15, 27,    # Team at index 1 - rank 1 (best)
        2, 2, 18, 6, 12, 24,    # Team at index 2 - rank 2
        3, 3, 16, 8, 8, 21,     # Team at index 3 - rank 3
        4, 4, 14, 10, 4, 18,    # Team at index 4 - rank 4
        5, 5, 12, 12, 0, 15,    # Team at index 5 - rank 5
        6, 6, 10, 14, -4, 12,   # Team at index 6 - rank 6
        7, 7, 8, 16, -8, 9,     # Team at index 7 - rank 7 (relegated)
        8, 8, 6, 18, -12, 6,    # Team at index 8 - rank 8 (relegated)
        9, 9, 4, 20, -16, 3,    # Team at index 9 - rank 9 (relegated)
        10, 10, 2, 22, -20, 0), # Team at index 10 - rank 10 (relegated)
      ncol = 6, byrow = TRUE
    ))
  })
  
  # Test
  baseline_2023 <- calculate_liga3_relegation_baseline("2023")
  baseline_2024 <- calculate_liga3_relegation_baseline("2024")
  
  # Should be different baselines
  expect_true(baseline_2024 > baseline_2023)
  
  # Specific values from the mock scenarios
  expect_equal(baseline_2023, liga3_2023$expected_baseline)
  expect_equal(baseline_2024, liga3_2024$expected_baseline)
  
  # Cleanup
  unlink(team_list_2023)
  unlink(team_list_2024)
})

test_that("temporary files are properly created and used in multi-season workflow", {
  # Create temporary directory for test
  temp_dir <- tempdir()
  
  # Mock file operations to simulate temporary file creation
  temp_files_2024 <- c(
    file.path(temp_dir, "TeamList_2024_League78_temp.csv"),
    file.path(temp_dir, "TeamList_2024_League80_temp.csv")
  )
  
  # Create mock temporary files
  bundesliga_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1800, 1650),
    stringsAsFactors = FALSE
  )
  
  liga3_data <- data.frame(
    TeamID = c(1320, 4259),
    ShortText = c("FCE", "AAC"),
    Promotion = c(0, 0),
    InitialELO = c(1150, 1080),
    stringsAsFactors = FALSE
  )
  
  write.table(bundesliga_data, temp_files_2024[1], sep = ";", row.names = FALSE, quote = FALSE)
  write.table(liga3_data, temp_files_2024[2], sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock load_previous_team_list to use temp files
  stub(load_previous_team_list, "list.files", function(path, pattern, ...) {
    if (grepl("TeamList_2024_League.*_temp", pattern)) {
      return(temp_files_2024)
    }
    return(character(0))
  })
  
  # Test
  result <- load_previous_team_list("2024")
  
  # Should load combined data from temporary files
  expect_equal(nrow(result), 4)
  expect_true(all(c(168, 167, 1320, 4259) %in% result$TeamID))
  expect_true(all(c("B04", "HOF", "FCE", "AAC") %in% result$ShortText))
  
  # Should have 2024 final ELOs, not initial
  expect_equal(result$InitialELO[result$TeamID == 1320], 1150)
  expect_equal(result$InitialELO[result$TeamID == 4259], 1080)
  
  # Cleanup
  unlink(temp_files_2024)
})

context("Multi-Season Integration - Circular Dependency Resolution")

test_that("ELO calculation works when TeamList file doesn't exist yet", {
  # Simulate scenario where TeamList_2024.csv doesn't exist but temp files do
  temp_dir <- tempdir()
  temp_files <- c(
    file.path(temp_dir, "TeamList_2024_League78_temp.csv"),
    file.path(temp_dir, "TeamList_2024_League80_temp.csv")
  )
  
  # Create temp files with team data
  temp_data1 <- data.frame(
    TeamID = c(168),
    ShortText = c("B04"),
    Promotion = c(0),
    InitialELO = c(1765),
    stringsAsFactors = FALSE
  )
  
  temp_data2 <- data.frame(
    TeamID = c(1320),
    ShortText = c("FCE"),
    Promotion = c(0),
    InitialELO = c(1100),
    stringsAsFactors = FALSE
  )
  
  write.table(temp_data1, temp_files[1], sep = ";", row.names = FALSE, quote = FALSE)
  write.table(temp_data2, temp_files[2], sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock functions for calculate_final_elos
  stub(calculate_final_elos, "list.files", function(path, pattern, ...) {
    if (grepl("TeamList_2024_League.*_temp", pattern)) {
      return(temp_files)
    }
    return(character(0))
  })
  
  stub(calculate_final_elos, "file.exists", function(path) {
    # Regular TeamList file doesn't exist
    !grepl("TeamList_2024.csv", path)
  })
  
  # Mock get_league_matches to return no matches (simplified)
  stub(calculate_final_elos, "get_league_matches", function(...) NULL)
  
  # Test - should not crash and should use temp files
  result <- calculate_final_elos("2024")
  
  # Should successfully create final ELOs from temp files
  expect_equal(nrow(result), 2)
  expect_true(all(c(168, 1320) %in% result$TeamID))
  expect_true(all(c(1765, 1100) %in% result$FinalELO))
  
  # Cleanup
  unlink(temp_files)
})

test_that("Liga3 baseline calculation works during multi-season processing", {
  # Create RCode directory if it doesn't exist
  if (!dir.exists("RCode")) {
    dir.create("RCode", showWarnings = FALSE)
  }
  
  # Test the specific scenario that was failing
  temp_dir <- tempdir()
  
  # Create main TeamList file that the function expects
  team_list_main <- file.path("RCode", "TeamList_2024.csv")
  # Create temporary Liga3 file (simulating mid-processing state)
  liga3_temp <- file.path(temp_dir, "TeamList_2024_League80_temp.csv")
  
  liga3_data <- data.frame(
    TeamID = c(1001, 1002, 1003, 1004, 1005, 1006),
    ShortText = c("T01", "T02", "T03", "T04", "T05", "T06"),
    Promotion = c(0, 0, 0, 0, 0, 0),
    InitialELO = c(1200, 1150, 1100, 1050, 1000, 950),
    stringsAsFactors = FALSE
  )
  
  # Write both files
  write.table(liga3_data, team_list_main, sep = ";", row.names = FALSE, quote = FALSE)
  write.table(liga3_data, liga3_temp, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Create mock Liga3 scenario inline for proper match data with all teams
  liga3_scenario <- list(
    matches = data.frame(
      fixture_date = "2024-05-01",
      teams_home_id = c(1001, 1002, 1003),
      teams_away_id = c(1004, 1005, 1006),
      goals_home = c(2, 1, 0),
      goals_away = c(1, 1, 2),
      fixture_status_short = rep("FT", 3),
      stringsAsFactors = FALSE
    )
  )
  
  # Mock the calculate_final_elos function to use temp files
  stub(calculate_liga3_relegation_baseline, "calculate_final_elos", function(season) {
    # Return data as if calculated from temp files
    return(data.frame(
      TeamID = liga3_data$TeamID,
      FinalELO = liga3_data$InitialELO,  # Simplified - no match processing
      stringsAsFactors = FALSE
    ))
  })
  
  stub(calculate_liga3_relegation_baseline, "get_league_matches", function(...) liga3_scenario$matches)
  
  # Mock the Tabelle function to return league standings with bottom 4 teams
  stub(calculate_liga3_relegation_baseline, "Tabelle", function(season, numberTeams, numberGames) {
    # Return mock league table with team rankings
    # Columns: team_number, rank, goals_for, goals_against, goal_diff, points
    # Teams 3, 4, 5, 6 are in relegation positions (ranks 3-6 out of 6)
    return(matrix(
      c(1, 1, 10, 5, 5, 9,    # Team 1001 - rank 1
        2, 2, 8, 6, 2, 6,     # Team 1002 - rank 2
        3, 3, 5, 7, -2, 3,    # Team 1003 - rank 3 (relegation)
        4, 4, 4, 8, -4, 3,    # Team 1004 - rank 4 (relegation)
        5, 5, 3, 9, -6, 1,    # Team 1005 - rank 5 (relegation)
        6, 6, 2, 10, -8, 0),  # Team 1006 - rank 6 (relegation)
      ncol = 6, byrow = TRUE
    ))
  })
  
  # Test
  baseline <- calculate_liga3_relegation_baseline("2024")
  
  # Should calculate from bottom 4 teams: 950, 1000, 1050, 1100
  expected_baseline <- mean(c(950, 1000, 1050, 1100))
  expect_equal(baseline, expected_baseline)
  
  # Should not be the default fallback
  expect_true(baseline != 1046)
  
  # Cleanup
  unlink(liga3_temp)
  unlink(team_list_main)
})

context("Multi-Season Integration - No Duplicate Prompts")

test_that("teams processed in 2024 are not prompted again in 2025", {
  # Setup: Teams from 2024 processing
  teams_2024_processed <- data.frame(
    TeamID = c(1320, 4259),
    ShortText = c("FCE", "AAC"),
    Promotion = c(0, 0),
    InitialELO = c(1150, 1080),
    stringsAsFactors = FALSE
  )
  
  # Same teams appear in 2025 API
  api_teams_2025 <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE),
    list(id = 4259, name = "Alemannia Aachen", is_second_team = FALSE)
  )
  
  # Mock final ELOs for 2025
  final_elos_2025 <- data.frame(
    TeamID = c(1320, 4259),
    FinalELO = c(1200, 1110),
    stringsAsFactors = FALSE
  )
  
  # Mock prompt function - should NOT be called
  mock_prompt <- mock(list(short_name = "XXX", initial_elo = 9999, promotion_value = 0))
  stub(process_league_teams, "prompt_for_team_info", mock_prompt)
  
  # Mock get_existing_team_data to find teams
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    match_row <- prev_list[prev_list$TeamID == team_id, ]
    if (nrow(match_row) == 0) return(NULL)
    return(list(
      short_name = match_row$ShortText[1],
      promotion_value = match_row$Promotion[1]
    ))
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Test
  result <- process_league_teams(api_teams_2025, "80", "2025", final_elos_2025, 1046, teams_2024_processed)
  
  # Should NOT call prompt_for_team_info
  expect_called(mock_prompt, 0)
  
  # Should use carryover data
  expect_length(result, 2)
  expect_equal(result[[1]]$short_name, "FCE")
  expect_equal(result[[2]]$short_name, "AAC")
  
  # Should use final ELO from 2025
  expect_equal(result[[1]]$initial_elo, 1200)
  expect_equal(result[[2]]$initial_elo, 1110)
})

test_that("genuinely new teams in 2025 are still prompted", {
  # Setup: 2024 teams + 1 new team in 2025
  teams_2024_processed <- data.frame(
    TeamID = c(1320),
    ShortText = c("FCE"),
    Promotion = c(0),
    InitialELO = c(1150),
    stringsAsFactors = FALSE
  )
  
  # API returns existing team + new team
  api_teams_2025 <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE),  # Existing
    list(id = 9999, name = "New Team FC", is_second_team = FALSE)       # New
  )
  
  final_elos_2025 <- data.frame(
    TeamID = c(1320),  # Only existing team has ELO
    FinalELO = c(1200),
    stringsAsFactors = FALSE
  )
  
  # Mock prompt function - should be called once for new team
  mock_prompt <- mock(list(short_name = "NEW", initial_elo = 1046, promotion_value = 0))
  stub(process_league_teams, "prompt_for_team_info", mock_prompt)
  
  # Mock get_existing_team_data
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    if (team_id == 1320) {
      return(list(short_name = "FCE", promotion_value = 0))
    }
    return(NULL)  # New team not found
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Test
  result <- process_league_teams(api_teams_2025, "80", "2025", final_elos_2025, 1046, teams_2024_processed)
  
  # Should call prompt_for_team_info once for new team
  expect_called(mock_prompt, 1)
  
  # Should have both teams
  expect_length(result, 2)
  
  # Existing team should use carryover data
  existing_team <- result[[which(sapply(result, function(t) t$id) == 1320)]]
  expect_equal(existing_team$short_name, "FCE")
  expect_equal(existing_team$initial_elo, 1200)
  
  # New team should use prompted data
  new_team <- result[[which(sapply(result, function(t) t$id) == 9999)]]
  expect_equal(new_team$short_name, "NEW")
  expect_equal(new_team$initial_elo, 1046)
})