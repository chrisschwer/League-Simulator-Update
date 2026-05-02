# Test the SpielCPP -> SpielNichtSimulieren contract at the level the season-transition workflow depends on.
# This file pins the default ModFaktor so changing it breaks this test.
#
# Why this exists: scripts/season_transition.R sources SpielCPP.R but the only
# direct test coverage of that path was the wrapper tests (test-SpielCPP.R,
# test-simulationsCPP.R, test-SaisonSimulierenCPP.R) which are being removed
# in Task 8 because the Rust engine is the production simulator.
# test-season-transition-regression.R does NOT exercise SpielCPP — confirmed
# by grep (zero hits for SpielCPP/simulationsCPP/SaisonSimulieren).
# This contract test is the season-transition workflow's safety net.

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
