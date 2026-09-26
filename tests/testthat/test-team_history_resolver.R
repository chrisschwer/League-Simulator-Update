# Unit tests for resolve_team_history.
#
# resolve_team_history is the existence-resolution unit extracted from
# process_league_teams in issue #73. It takes a team_id, the previous
# team list (used for ShortText/Promotion carryover), and the final ELOs
# table from the previous season. It returns one of three discriminated
# states the caller dispatches on.

library(testthat)

source("../../RCode/team_data_carryover.R")  # for get_existing_team_data
source("../../RCode/team_history_resolver.R")

prev_team_list <- data.frame(
  TeamID = c(168, 167),
  ShortText = c("B04", "HOF"),
  Promotion = c(0, 0),
  InitialELO = c(1765, 1628),
  stringsAsFactors = FALSE
)

final_elos <- data.frame(
  TeamID = c(168, 999),
  FinalELO = c(1800, 1234)
)

test_that("resolve_team_history returns 'carryover' when team is in previous_team_list", {
  result <- resolve_team_history(168, prev_team_list, final_elos)

  expect_equal(result$state, "carryover")
  expect_equal(result$previous_data$short_name, "B04")
  expect_equal(result$previous_data$promotion_value, 0)
  expect_equal(result$team_elo, 1800)
})

test_that("resolve_team_history returns 'carryover' with NULL team_elo when team is in previous_team_list but not in final_elos", {
  # Team 167 is in prev_team_list but not in final_elos
  result <- resolve_team_history(167, prev_team_list, final_elos)

  expect_equal(result$state, "carryover")
  expect_equal(result$previous_data$short_name, "HOF")
  expect_null(result$team_elo)
})

test_that("resolve_team_history returns 'fallback' when team is only in final_elos", {
  # Team 999 is in final_elos but not in prev_team_list
  result <- resolve_team_history(999, prev_team_list, final_elos)

  expect_equal(result$state, "fallback")
  expect_null(result$previous_data)
  expect_equal(result$team_elo, 1234)
})

test_that("resolve_team_history returns 'new' when team is in neither source", {
  result <- resolve_team_history(42, prev_team_list, final_elos)

  expect_equal(result$state, "new")
  expect_null(result$previous_data)
  expect_null(result$team_elo)
})

test_that("resolve_team_history handles NULL previous_team_list (first season)", {
  result <- resolve_team_history(168, NULL, final_elos)

  # No previous_team_list means no carryover possible — falls through
  # to final_elos check, which has 168, so 'fallback'.
  expect_equal(result$state, "fallback")
  expect_null(result$previous_data)
  expect_equal(result$team_elo, 1800)
})

test_that("resolve_team_history returns 'new' when both inputs are empty", {
  result <- resolve_team_history(168, NULL, data.frame(TeamID = integer(), FinalELO = numeric()))

  expect_equal(result$state, "new")
  expect_null(result$previous_data)
  expect_null(result$team_elo)
})

test_that("resolve_team_history handles NULL final_elos (first-ever season)", {
  # Mirrors the previous_team_list = NULL contract for symmetry.
  result <- resolve_team_history(168, prev_team_list, NULL)

  expect_equal(result$state, "carryover")
  expect_equal(result$previous_data$short_name, "B04")
  expect_null(result$team_elo)
})
