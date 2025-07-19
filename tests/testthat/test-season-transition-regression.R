# Regression test suite for season transition fixes
# Tests specific bugs that were identified and fixed

library(testthat)
library(mockery)

# Source required files
tryCatch({
  source("../../RCode/season_processor.R")
  source("../../RCode/elo_aggregation.R")
  source("../../RCode/interactive_prompts.R")
  source("../../RCode/csv_generation.R")
}, error = function(e) {
  warning("Could not source files, assuming functions are already loaded")
})

context("Regression Tests - Magical 1046 Issue")

test_that("Liga3 baseline is NOT 1046 for all season transitions", {
  # Test Issue: Liga3 baseline was hardcoded to 1046 for ALL seasons
  # Fix: Dynamic calculation based on bottom 4 Liga3 teams from each season
  
  # Mock different Liga3 scenarios for different seasons
  mock_matches_scenario_1 <- data.frame(
    fixture_date = c("2023-05-01"),
    teams_home_id = c(1001),
    teams_away_id = c(1002),
    goals_home = c(1),
    goals_away = c(0),
    fixture_status_short = c("FT"),
    stringsAsFactors = FALSE
  )
  
  mock_matches_scenario_2 <- data.frame(
    fixture_date = c("2024-05-01"),
    teams_home_id = c(2001),
    teams_away_id = c(2002),
    goals_home = c(2),
    goals_away = c(1),
    fixture_status_short = c("FT"),
    stringsAsFactors = FALSE
  )
  
  # Different ELO distributions (key fix point)
  mock_final_elos_2023 <- data.frame(
    TeamID = c(1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008),
    FinalELO = c(1250, 1200, 1150, 1100, 1050, 1000, 950, 900),  # Bottom 4: 900, 950, 1000, 1050
    stringsAsFactors = FALSE
  )
  
  mock_final_elos_2024 <- data.frame(
    TeamID = c(2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008),
    FinalELO = c(1350, 1300, 1250, 1200, 1150, 1100, 1050, 1000),  # Bottom 4: 1000, 1050, 1100, 1150
    stringsAsFactors = FALSE
  )
  
  # Mock functions
  stub(calculate_liga3_relegation_baseline, "get_league_matches", function(league, season) {
    if (season == "2023") return(mock_matches_scenario_1)
    if (season == "2024") return(mock_matches_scenario_2)
    return(NULL)
  })
  
  stub(calculate_liga3_relegation_baseline, "calculate_final_elos", function(season) {
    if (season == "2023") return(mock_final_elos_2023)
    if (season == "2024") return(mock_final_elos_2024)
    return(NULL)
  })
  
  # Test
  baseline_2023 <- calculate_liga3_relegation_baseline("2023")
  baseline_2024 <- calculate_liga3_relegation_baseline("2024")
  
  # REGRESSION: Should NOT both be 1046
  expect_false(baseline_2023 == 1046 && baseline_2024 == 1046)
  
  # Should be different values
  expect_true(baseline_2024 > baseline_2023)
  
  # Specific expected values
  expected_2023 <- mean(c(900, 950, 1000, 1050))   # 975
  expected_2024 <- mean(c(1000, 1050, 1100, 1150)) # 1075
  
  expect_equal(baseline_2023, expected_2023)
  expect_equal(baseline_2024, expected_2024)
})

test_that("new teams get season-specific baseline, not hardcoded 1046", {
  # Test Issue: New teams always got 1046 ELO regardless of relegation baseline
  # Fix: Use calculated Liga3 baseline for Liga3 new teams
  
  # Mock calculated baseline (not 1046)
  calculated_baseline <- 1123
  
  # New Liga3 team
  api_teams <- list(
    list(id = 9999, name = "New Liga3 Team", is_second_team = FALSE)
  )
  
  # No previous data (genuinely new team)
  final_elos <- data.frame(TeamID = numeric(), FinalELO = numeric())
  
  # Mock prompt to return baseline ELO
  mock_prompt <- mock(list(
    short_name = "NEW", 
    initial_elo = calculated_baseline,  # Should use baseline, not 1046
    promotion_value = 0
  ))
  stub(process_league_teams, "prompt_for_team_info", mock_prompt)
  
  # Test
  result <- process_league_teams(api_teams, "80", "2025", final_elos, calculated_baseline, NULL)
  
  # REGRESSION: Should use calculated baseline, not hardcoded 1046
  expect_equal(result[[1]]$initial_elo, calculated_baseline)
  expect_false(result[[1]]$initial_elo == 1046)
})

context("Regression Tests - ELO Carryover Issue")

test_that("teams retain performance-based ELO across seasons (B04 example)", {
  # Test Issue: B04 had same ELO (1765) in 2023 and 2025 despite successful seasons
  # Fix: Teams should use final ELO from previous season, not original initial ELO
  
  # B04 initial data
  previous_team_list <- data.frame(
    TeamID = c(168),
    ShortText = c("B04"),
    Promotion = c(0),
    InitialELO = c(1765),  # Original ELO
    stringsAsFactors = FALSE
  )
  
  # B04 after successful season (higher ELO)
  final_elos <- data.frame(
    TeamID = c(168),
    FinalELO = c(1823),  # DIFFERENT from initial - shows performance
    stringsAsFactors = FALSE
  )
  
  # API returns B04
  api_teams <- list(
    list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE)
  )
  
  # Mock team data carryover
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    if (team_id == 168) {
      return(list(short_name = "B04", promotion_value = 0))
    }
    return(NULL)
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Test
  result <- process_league_teams(api_teams, "78", "2025", final_elos, 1500, previous_team_list)
  
  # REGRESSION: Should use final ELO (1823), not initial ELO (1765)
  expect_equal(result[[1]]$initial_elo, 1823)
  expect_false(result[[1]]$initial_elo == 1765)  # Should NOT be original
  
  # Should retain team identity
  expect_equal(result[[1]]$short_name, "B04")
})

test_that("ELO progression works through multiple seasons", {
  # Test complete ELO progression: 2023→2024→2025
  
  # Season 2023 → 2024
  initial_elo_2023 <- 1500
  final_elo_2024 <- 1650  # Team performed well
  
  # Season 2024 → 2025  
  final_elo_2025 <- 1720  # Team continued to perform well
  
  # Mock team data for 2024 processing
  teams_2023 <- data.frame(
    TeamID = c(168),
    ShortText = c("B04"),
    Promotion = c(0),
    InitialELO = c(initial_elo_2023),
    stringsAsFactors = FALSE
  )
  
  final_elos_2024 <- data.frame(
    TeamID = c(168),
    FinalELO = c(final_elo_2024),
    stringsAsFactors = FALSE
  )
  
  # Process 2024
  api_teams <- list(list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE))
  
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    if (team_id == 168 && !is.null(prev_list)) {
      match_row <- prev_list[prev_list$TeamID == team_id, ]
      if (nrow(match_row) > 0) {
        return(list(short_name = match_row$ShortText[1], promotion_value = match_row$Promotion[1]))
      }
    }
    return(NULL)
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  result_2024 <- process_league_teams(api_teams, "78", "2024", final_elos_2024, 1500, teams_2023)
  
  # Create 2024 result for 2025 processing
  teams_2024 <- data.frame(
    TeamID = c(168),
    ShortText = c("B04"),
    Promotion = c(0),
    InitialELO = c(final_elo_2024),  # This is key
    stringsAsFactors = FALSE
  )
  
  final_elos_2025 <- data.frame(
    TeamID = c(168),
    FinalELO = c(final_elo_2025),
    stringsAsFactors = FALSE
  )
  
  # Process 2025
  result_2025 <- process_league_teams(api_teams, "78", "2025", final_elos_2025, 1500, teams_2024)
  
  # REGRESSION: Should show ELO progression
  expect_equal(result_2024[[1]]$initial_elo, final_elo_2024)  # 1650
  expect_equal(result_2025[[1]]$initial_elo, final_elo_2025)  # 1720
  
  # Should NOT be stuck at original value
  expect_false(result_2024[[1]]$initial_elo == initial_elo_2023)  # Not 1500
  expect_false(result_2025[[1]]$initial_elo == initial_elo_2023)  # Not 1500
})

context("Regression Tests - File Merge Issue")

test_that("final TeamList_YYYY.csv files are created, not just temp files", {
  # Test Issue: Only temporary files were created, no final merged files
  # Fix: merge_league_files creates final TeamList_YYYY.csv files
  
  # Create mock temp files
  temp_dir <- tempdir()
  temp_file1 <- file.path(temp_dir, "TeamList_2025_League78_temp.csv")
  temp_file2 <- file.path(temp_dir, "TeamList_2025_League80_temp.csv")
  
  bundesliga_data <- data.frame(
    TeamID = c(168, 167),
    ShortText = c("B04", "HOF"),
    Promotion = c(0, 0),
    InitialELO = c(1765, 1628),
    stringsAsFactors = FALSE
  )
  
  liga3_data <- data.frame(
    TeamID = c(1320, 4259),
    ShortText = c("FCE", "AAC"),
    Promotion = c(0, 0),
    InitialELO = c(1046, 1050),
    stringsAsFactors = FALSE
  )
  
  write.table(bundesliga_data, temp_file1, sep = ";", row.names = FALSE, quote = FALSE)
  write.table(liga3_data, temp_file2, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock generate_team_list_csv to simulate successful creation
  final_file <- file.path(temp_dir, "TeamList_2025.csv")
  stub(merge_league_files, "generate_team_list_csv", function(data, season, output_dir = "RCode") {
    # Verify all team data is combined
    expect_equal(nrow(data), 4)
    expect_true(all(c(168, 167, 1320, 4259) %in% data$TeamID))
    return(final_file)
  })
  
  # Test
  result <- merge_league_files(c(temp_file1, temp_file2), "2025")
  
  # REGRESSION: Should create final file, not return NULL
  expect_false(is.null(result))
  expect_equal(result, final_file)
  
  # Cleanup
  unlink(c(temp_file1, temp_file2))
})

test_that("file overwrite works in non-interactive mode", {
  # Test Issue: confirm_overwrite returned FALSE in non-interactive mode
  # Fix: Allow overwrite in non-interactive mode for season transition
  
  # Mock non-interactive mode
  stub(confirm_overwrite, "check_interactive_mode", function() FALSE)
  
  # Test
  result <- confirm_overwrite("existing_file.csv")
  
  # REGRESSION: Should allow overwrite in non-interactive mode
  expect_true(result)
  
  # Should NOT block file creation
  expect_false(result == FALSE)
})

context("Regression Tests - Duplicate Prompts Issue")

test_that("teams are NOT prompted twice in multi-season processing", {
  # Test Issue: Cottbus was prompted in 2024 AND 2025
  # Fix: Teams processed in 2024 should be recognized in 2025
  
  # Simulate Cottbus processed in 2024
  teams_2024_processed <- data.frame(
    TeamID = c(1320),
    ShortText = c("FCE"),  # User chose FCE in 2024
    Promotion = c(0),
    InitialELO = c(1046),
    stringsAsFactors = FALSE
  )
  
  # Cottbus appears again in 2025 API
  api_teams_2025 <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)
  )
  
  final_elos_2025 <- data.frame(
    TeamID = c(1320),
    FinalELO = c(1123),
    stringsAsFactors = FALSE
  )
  
  # Mock functions
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    if (team_id == 1320 && !is.null(prev_list)) {
      return(list(short_name = "FCE", promotion_value = 0))
    }
    return(NULL)
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Mock prompt - should NOT be called
  mock_prompt <- mock(list(short_name = "XXX", initial_elo = 9999, promotion_value = 0))
  stub(process_league_teams, "prompt_for_team_info", mock_prompt)
  
  # Test
  result <- process_league_teams(api_teams_2025, "80", "2025", final_elos_2025, 1046, teams_2024_processed)
  
  # REGRESSION: Should NOT prompt again (prompt_for_team_info not called)
  expect_called(mock_prompt, 0)
  
  # Should use previous data
  expect_equal(result[[1]]$short_name, "FCE")
  expect_equal(result[[1]]$initial_elo, 1123)  # Final ELO from 2025
})

test_that("short names are preserved across seasons", {
  # Test Issue: Team short names were regenerated instead of carried over
  # Fix: Use existing short names from previous_team_list
  
  # Teams with established short names
  previous_teams <- data.frame(
    TeamID = c(1320, 4259, 168),
    ShortText = c("FCE", "AAC", "B04"),  # User-established names
    Promotion = c(0, 0, 0),
    InitialELO = c(1046, 1050, 1765),
    stringsAsFactors = FALSE
  )
  
  # Same teams in API
  api_teams <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE),
    list(id = 4259, name = "Alemannia Aachen", is_second_team = FALSE),
    list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE)
  )
  
  final_elos <- data.frame(
    TeamID = c(1320, 4259, 168),
    FinalELO = c(1100, 1080, 1823),
    stringsAsFactors = FALSE
  )
  
  # Mock team data carryover
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    if (!is.null(prev_list)) {
      match_row <- prev_list[prev_list$TeamID == team_id, ]
      if (nrow(match_row) > 0) {
        return(list(
          short_name = match_row$ShortText[1],
          promotion_value = match_row$Promotion[1]
        ))
      }
    }
    return(NULL)
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Test
  result <- process_league_teams(api_teams, "80", "2025", final_elos, 1046, previous_teams)
  
  # REGRESSION: Should preserve original short names, not generate new ones
  short_names <- sapply(result, function(t) t$short_name)
  team_ids <- sapply(result, function(t) t$id)
  
  expect_equal(short_names[team_ids == 1320], "FCE")  # Not "ENE" or regenerated
  expect_equal(short_names[team_ids == 4259], "AAC")  # Not "ALE" or regenerated
  expect_equal(short_names[team_ids == 168], "B04")   # Not "BAY" or regenerated
})

context("Regression Tests - System Integration")

test_that("complete season transition creates expected file count", {
  # Test Issue: Incomplete team lists with wrong team counts
  # Fix: All leagues processed and merged correctly
  
  # Mock complete 3-league processing
  temp_dir <- tempdir()
  
  # Create temp files for all 3 leagues
  bundesliga_file <- file.path(temp_dir, "TeamList_2025_League78_temp.csv")
  zweite_file <- file.path(temp_dir, "TeamList_2025_League79_temp.csv")  
  liga3_file <- file.path(temp_dir, "TeamList_2025_League80_temp.csv")
  
  # Expected team counts per league
  bundesliga_data <- data.frame(
    TeamID = 1:18,  # 18 teams
    ShortText = paste0("B", sprintf("%02d", 1:18)),
    Promotion = rep(0, 18),
    InitialELO = rep(1600, 18),
    stringsAsFactors = FALSE
  )
  
  zweite_data <- data.frame(
    TeamID = 100:(100+17),  # 18 teams  
    ShortText = paste0("Z", sprintf("%02d", 1:18)),
    Promotion = rep(0, 18),
    InitialELO = rep(1400, 18),
    stringsAsFactors = FALSE
  )
  
  liga3_data <- data.frame(
    TeamID = 200:(200+19),  # 20 teams
    ShortText = paste0("L", sprintf("%02d", 1:20)),
    Promotion = rep(0, 20),
    InitialELO = rep(1200, 20),
    stringsAsFactors = FALSE
  )
  
  write.table(bundesliga_data, bundesliga_file, sep = ";", row.names = FALSE, quote = FALSE)
  write.table(zweite_data, zweite_file, sep = ";", row.names = FALSE, quote = FALSE)
  write.table(liga3_data, liga3_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock generate_team_list_csv
  final_file <- file.path(temp_dir, "TeamList_2025.csv")
  stub(merge_league_files, "generate_team_list_csv", function(data, season, output_dir = "RCode") {
    # Verify complete team count: 18 + 18 + 20 = 56 teams
    expect_equal(nrow(data), 56)
    
    # Verify all leagues represented
    expect_true(any(data$TeamID < 100))      # Bundesliga
    expect_true(any(data$TeamID >= 100 & data$TeamID < 200))  # 2. Bundesliga  
    expect_true(any(data$TeamID >= 200))     # 3. Liga
    
    return(final_file)
  })
  
  # Test
  result <- merge_league_files(c(bundesliga_file, zweite_file, liga3_file), "2025")
  
  # REGRESSION: Should create final merged file with all teams
  expect_false(is.null(result))
  expect_equal(result, final_file)
  
  # Cleanup
  unlink(c(bundesliga_file, zweite_file, liga3_file))
})

test_that("circular dependency resolution works end-to-end", {
  # Test Issue: Circular dependency between ELO calculation and team list creation
  # Fix: ELO calculation uses temporary files when main files don't exist
  
  temp_dir <- tempdir()
  
  # Simulate scenario: Processing 2024→2025, TeamList_2024.csv doesn't exist yet
  # but TeamList_2024_League*_temp.csv files do exist
  temp_files <- c(
    file.path(temp_dir, "TeamList_2024_League78_temp.csv"),
    file.path(temp_dir, "TeamList_2024_League80_temp.csv")
  )
  
  # Create temp files
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
  
  # Mock calculate_final_elos to find and use temp files
  stub(calculate_final_elos, "list.files", function(path, pattern, ...) {
    if (grepl("TeamList_2024_League.*_temp", pattern)) {
      return(temp_files)
    }
    return(character(0))
  })
  
  stub(calculate_final_elos, "file.exists", function(path) {
    # Main TeamList_2024.csv doesn't exist (being processed)
    !grepl("TeamList_2024\\.csv$", path)
  })
  
  # Mock get_league_matches (no actual matches for this test)
  stub(calculate_final_elos, "get_league_matches", function(...) NULL)
  
  # Test - should NOT crash with circular dependency
  expect_error(calculate_final_elos("2024"), NA)  # No error expected
  
  # Test Liga3 baseline calculation with temp files
  stub(calculate_liga3_relegation_baseline, "calculate_final_elos", function(season) {
    # Return mock data as if from temp files
    return(data.frame(
      TeamID = c(168, 1320, 1001, 1002, 1003, 1004),
      FinalELO = c(1765, 1100, 1050, 1000, 950, 900),
      stringsAsFactors = FALSE
    ))
  })
  
  mock_liga3_matches <- data.frame(
    teams_home_id = c(1320, 1001, 1002),
    teams_away_id = c(1001, 1002, 1003),
    stringsAsFactors = FALSE
  )
  
  stub(calculate_liga3_relegation_baseline, "get_league_matches", function(...) mock_liga3_matches)
  
  # Test baseline calculation - should work with temp files
  baseline <- calculate_liga3_relegation_baseline("2024")
  
  # REGRESSION: Should calculate baseline from temp file data, not default to 1046
  expected_baseline <- mean(c(900, 950, 1000, 1050))  # Bottom 4 from mock data
  expect_equal(baseline, expected_baseline)
  expect_false(baseline == 1046)
  
  # Cleanup
  unlink(temp_files)
})