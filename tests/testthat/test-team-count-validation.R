# Test file for team count validation

# Source the function to test
source("../../RCode/input_validation.R")

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
  # Create test file with too few teams (55)
  test_file <- tempfile(fileext = ".csv")
  
  test_data <- data.frame(
    TeamID = 1:55,
    ShortText = paste0("TM", 1:55),
    Promotion = rep(0, 55),
    InitialELO = rep(1500, 55)
  )
  write.table(test_data, test_file, sep = ";", row.names = FALSE, quote = FALSE)
  
  result <- validate_team_count(test_file)
  expect_false(result$valid)
  expect_true(grepl("Too few teams", result$message))
  
  # Clean up
  unlink(test_file)
})

test_that("validate_team_count rejects too many teams", {
  # Create test file with too many teams (63)
  test_file <- tempfile(fileext = ".csv")
  
  test_data <- data.frame(
    TeamID = 1:63,
    ShortText = paste0("TM", 1:63),
    Promotion = rep(0, 63),
    InitialELO = rep(1500, 63)
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