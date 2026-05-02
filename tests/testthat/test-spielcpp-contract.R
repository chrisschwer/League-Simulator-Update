# Test the SpielCPP contract that R-side code (season-transition operator
# workflow) depends on. The production loop now goes through the Rust seam
# (test-rust-required.R), but scripts/season_transition.R sources SpielCPP.R
# directly. After deletion of the CPP wrapper tests (test-SpielCPP.R,
# test-simulationsCPP.R, test-SaisonSimulierenCPP.R) and test-elo-basic.R,
# this file is the only R-side coverage of SpielCPP's behavior.
#
# Test 1: Pins the default ModFaktor (changing the default value breaks this).
# Test 2: Monte Carlo win-rate sanity for asymmetric teams (Simulieren=TRUE).
# Test 3: Monte Carlo home-advantage sanity (Simulieren=TRUE).

library(testthat)
library(Rcpp)

source("../../RCode/SpielCPP.R")
# cpp_wrappers.R not sourced: SpielCPP.R calls SpielNichtSimulieren directly (no wrapper dependency)
sourceCpp("../../RCode/SpielNichtSimulieren.cpp")

test_that("SpielCPP default ModFaktor is the season-transition contract value (20)", {
  # Two equal teams, home wins 2-0. Compare ELO delta with default vs explicit K=20.
  # If the default changes, the two calls diverge and this test fails.
  result_default <- SpielCPP(
    ELOHeim = 1500, ELOGast = 1500,
    ToreHeim = 2, ToreGast = 0,
    ZufallHeim = 0.5, ZufallGast = 0.5,
    Heimvorteil = 65,
    Simulieren = FALSE
  )
  result_explicit <- SpielCPP(
    ELOHeim = 1500, ELOGast = 1500,
    ToreHeim = 2, ToreGast = 0,
    ZufallHeim = 0.5, ZufallGast = 0.5,
    ModFaktor = 20, Heimvorteil = 65,
    Simulieren = FALSE
  )
  # Result is a NumericVector of length 5: [1]=home_new_ELO, [2]=away_new_ELO,
  # [3]=home_goals, [4]=away_goals, [5]=ELO_probability.
  # Compare home and away ELO — if default ever changes from 20, these diverge.
  expect_equal(result_default[1], result_explicit[1])
  expect_equal(result_default[2], result_explicit[2])
  # Sanity: home team's ELO went up after winning 2-0.
  expect_gt(result_default[1], 1500)
  # Sanity: away team's ELO went down.
  expect_lt(result_default[2], 1500)
})

test_that("Strong team beats weak team more often", {
  wins_strong <- 0
  n_simulations <- 1000

  set.seed(789)
  for (i in 1:n_simulations) {
    result <- SpielCPP(
      ELOHeim = 1800,  # Strong team
      ELOGast = 1200,  # Weak team
      ZufallHeim = runif(1),
      ZufallGast = runif(1),
      ModFaktor = 40,
      Heimvorteil = 100,
      Simulieren = TRUE
    )

    if (result[3] > result[4]) {
      wins_strong <- wins_strong + 1
    }
  }

  win_rate <- wins_strong / n_simulations

  # Strong team should win vast majority of games
  expect_true(win_rate > 0.85)
  expect_true(win_rate < 0.99)  # But not 100% - upsets can happen
})

test_that("Home advantage works correctly", {
  # Equal teams, but home team has advantage
  wins_home <- 0
  n_simulations <- 1000

  set.seed(101)
  for (i in 1:n_simulations) {
    result <- SpielCPP(
      ELOHeim = 1500,
      ELOGast = 1500,
      ZufallHeim = runif(1),
      ZufallGast = runif(1),
      ModFaktor = 40,
      Heimvorteil = 100,
      Simulieren = TRUE
    )

    if (result[3] > result[4]) {
      wins_home <- wins_home + 1
    }
  }

  win_rate_home <- wins_home / n_simulations

  # Home team with Heimvorteil=100 wins ~45% vs ~36% without advantage.
  # Bounds are set to catch: (a) missing/zeroed Heimvorteil (drops to ~36%),
  # (b) wrong sign (same direction), (c) wildly inflated advantage.
  expect_true(win_rate_home > 0.38)
  expect_true(win_rate_home < 0.55)
})
