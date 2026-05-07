# Unit tests for build_carryover_team_record and build_new_team_record.
#
# These are the record-building units extracted from process_league_teams
# in issue #73. They take pre-resolved history and return a fully-formed
# team record. build_new_team_record takes the prompt as an injected
# parameter so tests can pass a stub function directly.

library(testthat)

source("../../RCode/api_service.R")           # convert_second_team_short_name, get_team_short_name, get_league_name
source("../../RCode/interactive_prompts.R")   # generate_unique_short_name, prompt_for_team_info
source("../../RCode/team_data_carryover.R")
source("../../RCode/team_history_resolver.R")
source("../../RCode/team_record_builder.R")

test_that("build_carryover_team_record uses previous_data when state is 'carryover'", {
  team <- list(id = 168, name = "Bayer Leverkusen", is_second_team = FALSE)
  history <- list(
    state = "carryover",
    previous_data = list(short_name = "B04", promotion_value = 0),
    team_elo = 1800
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "78",
    liga3_baseline = 1100,
    existing_short_names = character()
  )

  expect_equal(result$id, 168)
  expect_equal(result$short_name, "B04")
  expect_equal(result$initial_elo, 1800)
  expect_equal(result$promotion_value, 0)
})

test_that("build_carryover_team_record uses baseline when team_elo is NULL", {
  team <- list(id = 167, name = "Hoffenheim", is_second_team = FALSE)
  history <- list(
    state = "carryover",
    previous_data = list(short_name = "HOF", promotion_value = 0),
    team_elo = NULL  # carryover with no final ELO
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "78",
    liga3_baseline = 1100,
    existing_short_names = character()
  )

  # league 78 (Bundesliga) baseline is 1500
  expect_equal(result$initial_elo, 1500)
  expect_equal(result$short_name, "HOF")
})

test_that("build_carryover_team_record uses liga3_baseline for league 80 with no team_elo", {
  team <- list(id = 1320, name = "Energie Cottbus", is_second_team = FALSE)
  history <- list(
    state = "carryover",
    previous_data = list(short_name = "FCE", promotion_value = 0),
    team_elo = NULL
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "80",
    liga3_baseline = 1046,
    existing_short_names = character()
  )

  expect_equal(result$initial_elo, 1046)
})

test_that("build_carryover_team_record generates fresh short_name when state is 'fallback'", {
  team <- list(id = 999, name = "Mystery FC", is_second_team = FALSE)
  history <- list(
    state = "fallback",
    previous_data = NULL,  # only in final_elos, no carryover record
    team_elo = 1234
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "78",
    liga3_baseline = 1100,
    existing_short_names = character()
  )

  # short_name comes from get_team_short_name on the API name
  expect_equal(result$short_name, get_team_short_name("Mystery FC"))
  expect_equal(result$initial_elo, 1234)
  expect_equal(result$promotion_value, 0)  # default for non-second-team
})

test_that("build_carryover_team_record uniquifies short_name in 'fallback' state when collision exists", {
  team <- list(id = 999, name = "Mystery FC", is_second_team = FALSE)
  history <- list(state = "fallback", previous_data = NULL, team_elo = 1234)

  collision <- get_team_short_name("Mystery FC")

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "78",
    liga3_baseline = 1100,
    existing_short_names = c(collision)
  )

  # uniquification happens via generate_unique_short_name
  expect_false(result$short_name == collision)
  expect_true(nchar(result$short_name) > 0)
})

test_that("build_carryover_team_record applies second-team conversion to short_name", {
  team <- list(id = 333, name = "Bayern München II", is_second_team = TRUE)
  history <- list(
    state = "carryover",
    previous_data = list(short_name = "FCB", promotion_value = -50),
    team_elo = 1500
  )

  result <- build_carryover_team_record(
    team,
    history,
    league_id = "80",
    liga3_baseline = 1046,
    existing_short_names = character()
  )

  # convert_second_team_short_name turns "FCB" into "FCB2" given is_second_team + promo=-50
  expect_equal(result$short_name, convert_second_team_short_name("FCB", TRUE, -50))
  expect_equal(result$promotion_value, -50)
})
