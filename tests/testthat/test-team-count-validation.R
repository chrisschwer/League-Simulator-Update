# Test file for team count validation

# validate_team_count() lebt seit #209 in season_processor.R (vormals
# input_validation.R); season_processor.R braucht seinerseits die Registry
# sowie transform_data.R/csv_generation.R (fuer merge_league_files() &co.)
# und sourct team_data_carryover.R selbst mit.
source("../../RCode/league_registry.R")
source("../../RCode/transform_data.R")
source("../../RCode/csv_generation.R")
source("../../RCode/season_processor.R")

test_that("validate_team_count validates correct range", {
  # Create a temporary test file with valid team count
  test_file <- tempfile(fileext = ".csv")
  
  # Create test data with 58 teams (valid)
  test_data <- data.frame(
    TeamID = 1:58,
    ShortText = paste0("TM", 1:58),
    Promotion = rep(0, 58),
    InitialELO = rep(1500, 58)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_true(result$valid)
  expect_equal(result$team_count, 58)
  
  # Clean up
  unlink(test_file)
})

test_that("validate_team_count rejects too few teams", {
  # Die Untergrenze folgt seit der Liga-Registry der kleinsten Liga (12 Teams,
  # Frauen-Bundesliga) statt der festen 56 fuer drei Ligen: Der Saisonwechsel
  # validiert auch Einzelligen-Dateien, nicht nur die zusammengefuehrte Liste.
  test_file <- tempfile(fileext = ".csv")

  test_data <- data.frame(
    TeamID = 1:8,
    ShortText = paste0("TM", 1:8),
    Promotion = rep(0, 8),
    InitialELO = rep(1500, 8)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_false(result$valid)
  expect_true(grepl("Too few teams", result$message))
  
  # Clean up
  unlink(test_file)
})

test_that("validate_team_count rejects too many teams", {
  # Die Obergrenze folgt der Summe aller zehn Ligen (mit Reserve, weil die
  # TeamList alle je aufgetretenen Teams fuehrt) statt der festen 62. Die
  # echte TeamList_2026 mit 237 Teams muss durchgehen -- das prueft
  # test-league-registry.R.
  test_file <- tempfile(fileext = ".csv")

  n <- 2000
  test_data <- data.frame(
    TeamID = 1:n,
    ShortText = paste0("TM", 1:n),
    Promotion = rep(0, n),
    InitialELO = rep(1500, n)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_false(result$valid)
  expect_true(grepl("Too many teams", result$message))
  
  # Clean up
  unlink(test_file)
})

test_that("validate_team_count handles file errors", {
  # Test non-existent file
  result <- validate_team_count("non_existent_file.csv")
  expect_false(result$valid)
  expect_true(grepl("File does not exist", result$message))
  
  # Test invalid CSV file
  test_file <- tempfile(fileext = ".csv")
  writeLines("This is not a valid CSV", test_file)
  
  result <- validate_team_count(test_file)
  expect_false(result$valid)
  expect_true(grepl("Too few teams", result$message))
  
  # Clean up
  unlink(test_file)
})

test_that("validate_team_count accepts boundary values", {
  # Test minimum valid count (56)
  test_file <- tempfile(fileext = ".csv")
  test_data <- data.frame(
    TeamID = 1:56,
    ShortText = paste0("TM", 1:56),
    Promotion = rep(0, 56),
    InitialELO = rep(1500, 56)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_true(result$valid)
  expect_equal(result$team_count, 56)
  
  unlink(test_file)
  
  # Test maximum valid count (62)
  test_file <- tempfile(fileext = ".csv")
  test_data <- data.frame(
    TeamID = 1:62,
    ShortText = paste0("TM", 1:62),
    Promotion = rep(0, 62),
    InitialELO = rep(1500, 62)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_true(result$valid)
  expect_equal(result$team_count, 62)
  
  unlink(test_file)
})