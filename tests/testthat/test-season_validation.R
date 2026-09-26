# Test suite for season validation functionality

library(testthat)
library(mockery)

# Source required files
source("../../RCode/season_validation.R")

context("Season Validation")

test_that("validate_season_completion throws error for incomplete season", {
  # Mock API to return season with unplayed matches
  mock_response <- list(
    response = list(
      list(fixture = list(status = list(short = "FT"))),  # Finished
      list(fixture = list(status = list(short = "NS"))),  # Not Started
      list(fixture = list(status = list(short = "PST")))  # Postponed
    )
  )
  
  # Mock httr::GET and httr::content
  stub(validate_season_completion, "httr::GET", function(...) {
    structure(list(), class = "response")
  })
  stub(validate_season_completion, "httr::status_code", 200)
  stub(validate_season_completion, "httr::content", mock_response)
  
  expect_error(
    validate_season_completion(2024),
    "Season 2024 not finished, no season transition possible."
  )
})

test_that("validate_season_completion passes for completed season", {
  # All matches finished
  mock_response <- list(
    response = list(
      list(fixture = list(status = list(short = "FT"))),
      list(fixture = list(status = list(short = "FT"))),
      list(fixture = list(status = list(short = "AET"))),  # After Extra Time
      list(fixture = list(status = list(short = "PEN")))   # After Penalties
    )
  )
  
  # Mock httr functions
  stub(validate_season_completion, "httr::GET", function(...) {
    structure(list(), class = "response")
  })
  stub(validate_season_completion, "httr::status_code", 200)
  stub(validate_season_completion, "httr::content", mock_response)
  
  expect_true(validate_season_completion(2024))
})

test_that("validate_season_completion handles API failures gracefully", {
  # Mock API failure
  stub(validate_season_completion, "httr::GET", function(...) {
    structure(list(), class = "response")
  })
  stub(validate_season_completion, "httr::status_code", 500)
  
  # Should return FALSE on API failure
  expect_false(validate_season_completion(2024))
})

test_that("validate_season_completion handles empty response", {
  # Mock empty response
  mock_response <- list(response = NULL)
  
  stub(validate_season_completion, "httr::GET", function(...) {
    structure(list(), class = "response")
  })
  stub(validate_season_completion, "httr::status_code", 200)
  stub(validate_season_completion, "httr::content", mock_response)
  
  # Should handle gracefully
  expect_false(validate_season_completion(2024))
})

context("Season Range Validation")

test_that("validate_season_range validates year format", {
  # Invalid year format
  expect_error(
    validate_season_range("20XX", "2025"),
    "Seasons must be valid 4-digit years"
  )
  
  expect_error(
    validate_season_range("2024", "20YY"),
    "Seasons must be valid 4-digit years"
  )
})

test_that("validate_season_range enforces reasonable year bounds", {
  # Too early
  expect_error(
    validate_season_range("1999", "2024"),
    "Source season must be between 2000 and 2030"
  )
  
  # Too late
  expect_error(
    validate_season_range("2024", "2031"),
    "Target season must be between 2000 and 2030"
  )
})

test_that("validate_season_range enforces logical progression", {
  # Target before source
  expect_error(
    validate_season_range("2025", "2024"),
    "Target season must be after source season"
  )
  
  # Same year
  expect_error(
    validate_season_range("2024", "2024"),
    "Target season must be after source season"
  )
})

test_that("validate_season_range limits range size", {
  # Too large range
  expect_error(
    validate_season_range("2010", "2025"),
    "Season range too large. Maximum 10 seasons supported."
  )
})

test_that("validate_season_range checks source season completion", {
  # Mock incomplete season
  stub(validate_season_range, "validate_season_completion", FALSE)
  
  expect_error(
    validate_season_range("2024", "2025"),
    "Source season 2024 is not complete or data not available"
  )
})

test_that("validate_season_range warns about existing files", {
  # Mock file existence
  stub(validate_season_range, "file.exists", function(path) {
    grepl("TeamList_2025.csv", path)
  })
  
  # Mock season completion
  stub(validate_season_range, "validate_season_completion", TRUE)
  
  # Should warn but not error
  expect_warning(
    result <- validate_season_range("2024", "2025"),
    "files already exist and will be overwritten"
  )
  
  expect_true(result)
})

context("API Access Validation")

test_that("validate_api_access checks for API key", {
  # Mock missing API key
  stub(validate_api_access, "Sys.getenv", function(key) {
    if (key == "RAPIDAPI_KEY") return("")
    return(NULL)
  })
  
  expect_error(
    validate_api_access(),
    "RAPIDAPI_KEY environment variable not set"
  )
})

test_that("validate_api_access tests API connectivity", {
  # Mock successful API response
  stub(validate_api_access, "Sys.getenv", "test-api-key")
  stub(validate_api_access, "httr::GET", function(...) {
    structure(list(), class = "response")
  })
  stub(validate_api_access, "httr::status_code", 200)
  
  expect_true(validate_api_access())
})

test_that("validate_api_access handles API errors", {
  # Mock API error
  stub(validate_api_access, "Sys.getenv", "test-api-key")
  stub(validate_api_access, "httr::GET", function(...) {
    structure(list(), class = "response")
  })
  stub(validate_api_access, "httr::status_code", 403)
  
  expect_false(validate_api_access())
})

context("Helper Functions")

test_that("get_seasons_to_process returns correct range", {
  result <- get_seasons_to_process("2020", "2024")
  expect_equal(result, c(2021, 2022, 2023, 2024))
  
  result <- get_seasons_to_process("2023", "2024")
  expect_equal(result, c(2024))
  
  # Adjacent years
  result <- get_seasons_to_process("2023", "2025")
  expect_equal(result, c(2024, 2025))
})

test_that("check_existing_files identifies existing files", {
  # Mock file existence
  stub(check_existing_files, "file.exists", function(path) {
    grepl("TeamList_2024.csv", path)
  })
  
  # Should find existing file
  result <- check_existing_files("2024")
  expect_equal(result, "RCode/TeamList_2024.csv")
  
  # Should return NULL for non-existing
  result <- check_existing_files("2025")
  expect_null(result)
})