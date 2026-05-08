# Tests for the season-transition validator escalations introduced by issue #74.
#
# 1. process_single_season: validate_team_count failure must abort (return
#    success=FALSE), no longer just warn and return success=TRUE.
# 2. process_season_transition: validate_season_processing failure at end of
#    pipeline must produce success=FALSE.

library(testthat)
library(mockery)

source("../../RCode/season_processor.R")
source("../../RCode/input_validation.R")

test_that("process_single_season fails when validate_team_count rejects merged file", {
  # Stub all the network-and-CSV-touching helpers process_single_season calls
  # before validate_team_count. We only care that, when validate_team_count
  # returns valid=FALSE, the function returns success=FALSE.
  stub(process_single_season, "validate_season_completion", TRUE)
  stub(process_single_season, "load_previous_team_list", data.frame())
  stub(process_single_season, "calculate_final_elos", data.frame())
  stub(process_single_season, "calculate_liga3_relegation_baseline", 1100)
  stub(process_single_season, "fetch_all_leagues_teams", list("78" = list(list(id = 1))))
  stub(process_single_season, "process_league_teams", list(list(id = 1)))
  stub(process_single_season, "generate_league_csv", "RCode/TeamList_2099_League78.csv")
  stub(process_single_season, "merge_league_files", "RCode/TeamList_2099.csv")
  stub(process_single_season, "get_league_name", "Bundesliga")
  stub(process_single_season, "validate_team_count", list(
    valid = FALSE,
    message = "Too few teams: 5 - expected at least 56"
  ))

  result <- process_single_season("2099", "2098")

  expect_false(result$success)
  expect_match(result$error, "Too few teams", fixed = TRUE)
})

test_that("process_season_transition fails when end-of-pipeline validate_season_processing rejects target season", {
  # Stub the inner pipeline so the loop succeeds, but make the new end-of-pipeline
  # validate_season_processing call return valid=FALSE.
  stub(process_season_transition, "display_welcome_message", invisible(NULL))
  stub(process_season_transition, "validate_season_range", invisible(NULL))
  stub(process_season_transition, "validate_api_access", TRUE)
  stub(process_season_transition, "get_seasons_to_process", "2099")
  stub(process_season_transition, "process_single_season", list(
    success = TRUE,
    teams_processed = 60,
    files_created = c("RCode/TeamList_2099.csv")
  ))
  stub(process_season_transition, "display_progress", invisible(NULL))
  stub(process_season_transition, "display_season_summary", invisible(NULL))
  stub(process_season_transition, "display_completion_message", invisible(NULL))
  stub(process_season_transition, "validate_season_processing", list(
    valid = FALSE,
    message = "Duplicate team IDs found"
  ))

  result <- process_season_transition("2098", "2099")

  expect_false(result$success)
  expect_match(result$error, "Duplicate team IDs", fixed = TRUE)
})
