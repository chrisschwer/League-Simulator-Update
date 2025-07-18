# Test file for second team short name conversion

# Source the function to test
source("../../RCode/api_service.R")

test_that("convert_second_team_short_name handles second teams correctly", {
  # Test regular second team conversion
  expect_equal(convert_second_team_short_name("HOF", TRUE, 0), "HO2")
  expect_equal(convert_second_team_short_name("FCB", TRUE, 0), "FC2")
  expect_equal(convert_second_team_short_name("BVB", TRUE, 0), "BV2")
})

test_that("convert_second_team_short_name handles promotion value -50", {
  # Test with promotion value -50
  expect_equal(convert_second_team_short_name("HOF", FALSE, -50), "HO2")
  expect_equal(convert_second_team_short_name("FCK", FALSE, -50), "FC2")
})

test_that("convert_second_team_short_name leaves regular teams unchanged", {
  # Test regular teams (not second teams)
  expect_equal(convert_second_team_short_name("HOF", FALSE, 0), "HOF")
  expect_equal(convert_second_team_short_name("FCB", FALSE, 0), "FCB")
  expect_equal(convert_second_team_short_name("BVB", FALSE, 0), "BVB")
})

test_that("convert_second_team_short_name handles edge cases", {
  # Test NULL and NA
  expect_true(is.null(convert_second_team_short_name(NULL, TRUE, -50)))
  expect_true(is.na(convert_second_team_short_name(NA, TRUE, -50)))
  
  # Test short names longer than 3 characters
  expect_equal(convert_second_team_short_name("LONG", TRUE, 0), "LO2")
  
  # Test 2 character names
  expect_equal(convert_second_team_short_name("AB", TRUE, 0), "AB")
})

test_that("detect_second_teams identifies all patterns", {
  # Test all second team patterns
  expect_true(detect_second_teams("Hoffenheim II"))
  expect_true(detect_second_teams("Bayern München 2"))
  expect_true(detect_second_teams("FC Bayern 2"))
  expect_true(detect_second_teams("Borussia Dortmund U21"))
  expect_true(detect_second_teams("Borussia Dortmund U-21"))
  expect_true(detect_second_teams("Borussia Dortmund U23"))
  expect_true(detect_second_teams("Borussia Dortmund U-23"))
  expect_true(detect_second_teams("Schalke 04 B"))
  expect_true(detect_second_teams("Frankfurt Reserve"))
  expect_true(detect_second_teams("Team Reserves"))
  
  # Test regular teams
  expect_false(detect_second_teams("Hoffenheim"))
  expect_false(detect_second_teams("Bayern München"))
  expect_false(detect_second_teams("Borussia Dortmund"))
  expect_false(detect_second_teams("1. FC Nürnberg"))
  expect_false(detect_second_teams("2. Bundesliga Team"))
})