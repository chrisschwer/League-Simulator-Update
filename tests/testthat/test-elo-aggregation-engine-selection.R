# Engine-selection regression net for update_elos_for_match.
#
# Phase-2 Option B (issue #102) collapsed elo_aggregation.R onto the pure-R
# calculate_elo_update path. This file used to pin the C++/R cross-engine
# equivalence (PR #100); after the C++ engine deletion it pins only the R path.
#
# The original engine-equivalence sweep is preserved in git history at the
# pre-deletion commit; rerun it before reintroducing any non-R ELO engine.

library(testthat)

fixture_match <- function() {
  data.frame(
    teams_home_id = 1L,
    teams_away_id = 2L,
    goals_home = 2,
    goals_away = 0,
    stringsAsFactors = FALSE
  )
}

fixture_elos <- function() {
  data.frame(
    TeamID = c(1L, 2L),
    CurrentELO = c(1500, 1500),
    stringsAsFactors = FALSE
  )
}

test_that("update_elos_for_match returns expected ELOs via the R primitive", {
  result <- update_elos_for_match(fixture_elos(), fixture_match())

  # Hand-computed from calculate_elo_update with k_factor=20, home_advantage=100,
  # ELOs (1500, 1500), goals (2, 0):
  #   elo_diff       = 1500 - 1500 - 100 = -100, clamped to [-400,400] = -100
  #   expected_prob  = 1 / (1 + 10^(-100/400)) = 0.6400649...
  #   goal_diff      = 2 - 0 = 2
  #   actual_result  = (sign(2) + 1) / 2 = 1.0
  #   goal_modifier  = sqrt(max(abs(2),1)) = sqrt(2) = 1.41421356...
  #   elo_change     = (1.0 - 0.6400649) * 1.41421356 * 20 = 10.18028...
  expected_home <- 1500 + 10.18028
  expected_away <- 1500 - 10.18028

  expect_equal(result$CurrentELO[result$TeamID == 1L], expected_home, tolerance = 1e-4)
  expect_equal(result$CurrentELO[result$TeamID == 2L], expected_away, tolerance = 1e-4)
})

test_that("calculate_elo_update is the only ELO primitive in scope", {
  # After issue #102 / Option B, no compiled C++ ELO function should be
  # reachable. SpielNichtSimulieren must NOT exist — if a future change
  # reintroduces it, this test surfaces it.
  expect_false(exists("SpielNichtSimulieren"),
               info = "SpielNichtSimulieren was deleted in #102 / Option B")
  expect_true(exists("calculate_elo_update"),
              info = "calculate_elo_update is the load-bearing ELO primitive")
})
