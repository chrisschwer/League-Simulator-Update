# Test suite for season processor fixes
# Tests the enhanced team matching logic and debugging features

library(testthat)
library(mockery)

# Functions should be loaded by helper-test-setup.R

context("Season Processor Fixes - Team Matching Priority")

test_that("process_league_teams prioritizes previous_team_list over final_elos", {
  # Setup: Team exists in previous_team_list but not in final_elos
  previous_team_list <- data.frame(
    TeamID = c(1320),
    ShortText = c("FCE"),
    Promotion = c(0),
    InitialELO = c(1100),
    stringsAsFactors = FALSE
  )
  
  # final_elos doesn't contain this team (simulating circular dependency scenario)
  final_elos <- data.frame(
    TeamID = numeric(),
    FinalELO = numeric(),
    stringsAsFactors = FALSE
  )
  
  # API returns the team
  api_teams <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)
  )
  
  # Mock functions that might be called
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    if (team_id == 1320 && !is.null(prev_list)) {
      return(list(short_name = "FCE", promotion_value = 0))
    }
    return(NULL)
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Test
  result <- process_league_teams(api_teams, "80", "2025", final_elos, 1046, previous_team_list)
  
  # Should find team in previous_team_list and NOT prompt for new team info
  expect_length(result, 1)
  expect_equal(result[[1]]$short_name, "FCE")
  expect_equal(result[[1]]$id, 1320)
  
  # Should use baseline ELO since no final_elos available
  expect_equal(result[[1]]$initial_elo, 1046)
})

test_that("process_league_teams uses final_elos when available", {
  # Setup: Team exists in both previous_team_list and final_elos
  previous_team_list <- data.frame(
    TeamID = c(1320),
    ShortText = c("FCE"),
    Promotion = c(0),
    InitialELO = c(1100),
    stringsAsFactors = FALSE
  )
  
  final_elos <- data.frame(
    TeamID = c(1320),
    FinalELO = c(1234),  # Different from initial
    stringsAsFactors = FALSE
  )
  
  api_teams <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)
  )
  
  # Mock functions
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    if (team_id == 1320) {
      return(list(short_name = "FCE", promotion_value = 0))
    }
    return(NULL)
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Test
  result <- process_league_teams(api_teams, "80", "2025", final_elos, 1046, previous_team_list)
  
  # Should use final ELO, not baseline
  expect_equal(result[[1]]$initial_elo, 1234)
  expect_equal(result[[1]]$short_name, "FCE")
})

test_that("process_league_teams falls back to prompting for genuinely new teams", {
  # Setup: Team doesn't exist in either previous_team_list or final_elos
  previous_team_list <- data.frame(
    TeamID = c(1111),
    ShortText = c("OLD"),
    Promotion = c(0),
    InitialELO = c(1000),
    stringsAsFactors = FALSE
  )
  
  final_elos <- data.frame(
    TeamID = c(1111),
    FinalELO = c(1050),
    stringsAsFactors = FALSE
  )
  
  api_teams <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)  # New team
  )
  
  # Mock prompt_for_team_info
  mock_prompt <- mock(list(short_name = "FCE", initial_elo = 1046, promotion_value = 0))
  stub(process_league_teams, "prompt_for_team_info", mock_prompt)
  
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    return(NULL)  # Team not found
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Test
  result <- process_league_teams(api_teams, "80", "2025", final_elos, 1046, previous_team_list)
  
  # Should prompt for new team
  expect_called(mock_prompt, 1)
  expect_equal(result[[1]]$short_name, "FCE")
  expect_equal(result[[1]]$initial_elo, 1046)
})

context("Season Processor Fixes - File Merge Process")

test_that("merge_league_files creates final TeamList file", {
  # Create temporary test files
  temp_dir <- tempdir()
  temp_file1 <- file.path(temp_dir, "TeamList_2025_League78_temp.csv")
  temp_file2 <- file.path(temp_dir, "TeamList_2025_League80_temp.csv")
  
  # Create test data
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
  
  # Mock generate_team_list_csv
  mock_generate_csv <- mock(file.path(temp_dir, "TeamList_2025.csv"))
  stub(merge_league_files, "generate_team_list_csv", mock_generate_csv)
  
  # Test
  result <- merge_league_files(c(temp_file1, temp_file2), "2025")
  
  # Should call generate_team_list_csv with combined data
  expect_called(mock_generate_csv, 1)
  
  # Check the data passed to generate_team_list_csv
  args <- mock_args(mock_generate_csv)[[1]]
  combined_data <- args[[1]]
  
  expect_equal(nrow(combined_data), 4)
  expect_true(all(c(168, 167, 1320, 4259) %in% combined_data$TeamID))
  expect_true(all(c("B04", "HOF", "FCE", "AAC") %in% combined_data$ShortText))
  
  # Should return the generated file path
  expect_equal(result, file.path(temp_dir, "TeamList_2025.csv"))
  
  # Cleanup
  unlink(c(temp_file1, temp_file2))
})

test_that("merge_league_files handles empty league files gracefully", {
  # Create temp files with one empty file
  temp_dir <- tempdir()
  temp_file1 <- file.path(temp_dir, "TeamList_2025_League78_temp.csv")
  temp_file2 <- file.path(temp_dir, "TeamList_2025_League79_temp.csv")
  
  # Only first file has data
  valid_data <- data.frame(
    TeamID = c(168),
    ShortText = c("B04"),
    Promotion = c(0),
    InitialELO = c(1765),
    stringsAsFactors = FALSE
  )
  
  write.table(valid_data, temp_file1, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Create empty file
  writeLines("TeamID;ShortText;Promotion;InitialELO", temp_file2)
  
  # Mock generate_team_list_csv
  mock_generate_csv <- mock(file.path(temp_dir, "TeamList_2025.csv"))
  stub(merge_league_files, "generate_team_list_csv", mock_generate_csv)
  
  # Test
  result <- merge_league_files(c(temp_file1, temp_file2), "2025")
  
  # Should still work with just the valid data
  expect_called(mock_generate_csv, 1)
  args <- mock_args(mock_generate_csv)[[1]]
  combined_data <- args[[1]]
  
  expect_equal(nrow(combined_data), 1)
  expect_equal(combined_data$TeamID[1], 168)
  
  # Cleanup
  unlink(c(temp_file1, temp_file2))
})

test_that("merge_league_files sorts teams by TeamID", {
  # Create temp files with unsorted data
  temp_dir <- tempdir()
  temp_file1 <- file.path(temp_dir, "TeamList_2025_League78_temp.csv")
  
  # Unsorted data
  unsorted_data <- data.frame(
    TeamID = c(167, 168, 165),  # Unsorted
    ShortText = c("HOF", "B04", "BVB"),
    Promotion = c(0, 0, 0),
    InitialELO = c(1628, 1765, 1885),
    stringsAsFactors = FALSE
  )
  
  write.table(unsorted_data, temp_file1, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock generate_team_list_csv to capture data
  captured_data <- NULL
  mock_generate_csv <- function(data, season) {
    captured_data <<- data
    return(file.path(temp_dir, paste0("TeamList_", season, ".csv")))
  }
  
  stub(merge_league_files, "generate_team_list_csv", mock_generate_csv)
  
  # Test
  result <- merge_league_files(c(temp_file1), "2025")
  
  # Should be sorted by TeamID
  expect_equal(captured_data$TeamID, c(165, 167, 168))
  expect_equal(captured_data$ShortText, c("BVB", "HOF", "B04"))
  
  # Cleanup
  unlink(temp_file1)
})

context("Season Processor Fixes - Enhanced Debugging")

test_that("process_league_teams logs ELO decisions", {
  # Setup
  previous_team_list <- data.frame(
    TeamID = c(168),
    ShortText = c("B04"),
    Promotion = c(0),
    InitialELO = c(1765),
    stringsAsFactors = FALSE
  )
  
  final_elos <- data.frame(
    TeamID = c(168),
    FinalELO = c(1823),  # Different from initial
    stringsAsFactors = FALSE
  )
  
  api_teams <- list(
    list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE)
  )
  
  # Capture console output
  output <- capture.output({
    result <- process_league_teams(api_teams, "78", "2025", final_elos, 1500, previous_team_list)
  })
  
  # Should log the ELO decision
  expect_true(any(grepl("Using final ELO", output)))
  expect_true(any(grepl("1823", output)))
  expect_true(any(grepl("Bayer Leverkusen", output)))
})

test_that("process_league_teams logs baseline ELO usage", {
  # Setup with no final ELO available
  previous_team_list <- data.frame(
    TeamID = c(1320),
    ShortText = c("FCE"),
    Promotion = c(0),
    InitialELO = c(1046),
    stringsAsFactors = FALSE
  )
  
  final_elos <- data.frame(
    TeamID = numeric(),
    FinalELO = numeric(),
    stringsAsFactors = FALSE
  )
  
  api_teams <- list(
    list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)
  )
  
  # Mock get_existing_team_data
  stub(process_league_teams, "get_existing_team_data", function(team_id, prev_list) {
    return(list(short_name = "FCE", promotion_value = 0))
  })
  
  stub(process_league_teams, "convert_second_team_short_name", function(short_name, is_second, promo) {
    return(short_name)
  })
  
  # Capture console output
  output <- capture.output({
    result <- process_league_teams(api_teams, "80", "2025", final_elos, 1046, previous_team_list)
  })
  
  # Should log baseline usage
  expect_true(any(grepl("Using baseline ELO", output)))
  expect_true(any(grepl("1046", output)))
})

context("Season Processor Fixes - Error Handling")

test_that("merge_league_files handles missing temp files gracefully", {
  # Test with non-existent files
  non_existent_files <- c("missing1.csv", "missing2.csv")
  
  # Should not crash
  result <- merge_league_files(non_existent_files, "2025")
  
  # Should return NULL when no valid files
  expect_null(result)
})

test_that("merge_league_files handles CSV generation failure", {
  # Create valid temp file
  temp_dir <- tempdir()
  temp_file <- file.path(temp_dir, "TeamList_2025_League78_temp.csv")
  
  valid_data <- data.frame(
    TeamID = c(168),
    ShortText = c("B04"),
    Promotion = c(0),
    InitialELO = c(1765),
    stringsAsFactors = FALSE
  )
  
  write.table(valid_data, temp_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock generate_team_list_csv to fail
  stub(merge_league_files, "generate_team_list_csv", function(...) {
    stop("CSV generation failed")
  })
  
  # Test
  result <- merge_league_files(c(temp_file), "2025")
  
  # Should handle error gracefully
  expect_null(result)
  
  # Cleanup
  unlink(temp_file)
})

context("Season Processor Fixes - Team Data Carryover Enhancement")

test_that("load_previous_team_list prioritizes temporary files", {
  # Create both regular and temporary files
  temp_dir <- tempdir()
  
  # Create regular file
  regular_file <- file.path(temp_dir, "TeamList_2024.csv")
  regular_data <- data.frame(
    TeamID = c(111),
    ShortText = c("OLD"),
    Promotion = c(0),
    InitialELO = c(1000),
    stringsAsFactors = FALSE
  )
  write.table(regular_data, regular_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Create temporary files (should be prioritized)
  temp_file1 <- file.path(temp_dir, "TeamList_2024_League78_temp.csv")
  temp_file2 <- file.path(temp_dir, "TeamList_2024_League80_temp.csv")
  
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
    InitialELO = c(1046),
    stringsAsFactors = FALSE
  )
  
  write.table(temp_data1, temp_file1, sep = ";", row.names = FALSE, quote = FALSE)
  write.table(temp_data2, temp_file2, sep = ";", row.names = FALSE, quote = FALSE)
  
  # Mock list.files to find temp files
  stub(load_previous_team_list, "list.files", function(path, pattern, ...) {
    if (grepl("TeamList_2024_League.*_temp", pattern)) {
      return(c(temp_file1, temp_file2))
    }
    return(character(0))
  })
  
  # Test
  result <- load_previous_team_list("2024")
  
  # Should use temp files, not regular file
  expect_equal(nrow(result), 2)
  expect_true(all(c(168, 1320) %in% result$TeamID))
  expect_true(all(c("B04", "FCE") %in% result$ShortText))
  
  # Should NOT contain the regular file data
  expect_false(111 %in% result$TeamID)
  
  # Cleanup
  unlink(c(regular_file, temp_file1, temp_file2))
})