# Basic ELO Tests

library(testthat)
source("../../RCode/SpielCPP.R")
source("../../RCode/RcppExports.R")

test_that("ELO updates correctly after match", {
  # Test home win
  result <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 2,
    GoalsAway = 0,
    ModFaktor = 40,
    Heimvorteil = 100
  )
  
  # Home team won, so ELO should increase
  expect_true(result[1] > 1500)
  expect_true(result[2] < 1500)
  
  # ELO changes should be equal and opposite
  home_change <- result[1] - 1500
  away_change <- result[2] - 1500
  expect_equal(home_change, -away_change, tolerance = 0.01)
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
  
  # Home team should win more than 50% due to advantage
  expect_true(win_rate_home > 0.55)
  expect_true(win_rate_home < 0.70)
})

test_that("Draw results in smaller ELO changes", {
  # Home win
  win_result <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 2,
    GoalsAway = 0,
    ModFaktor = 40,
    Heimvorteil = 0  # No home advantage for clearer comparison
  )
  
  # Draw
  draw_result <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 1,
    GoalsAway = 1,
    ModFaktor = 40,
    Heimvorteil = 0
  )
  
  win_change <- abs(win_result[1] - 1500)
  draw_change <- abs(draw_result[1] - 1500)
  
  # Draw should result in smaller ELO change than win
  expect_true(draw_change < win_change)
})

test_that("Goal difference affects ELO change magnitude", {
  # 1-0 win
  small_win <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 1,
    GoalsAway = 0,
    ModFaktor = 40,
    Heimvorteil = 0
  )
  
  # 3-0 win
  big_win <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 3,
    GoalsAway = 0,
    ModFaktor = 40,
    Heimvorteil = 0
  )
  
  small_change <- abs(small_win[1] - 1500)
  big_change <- abs(big_win[1] - 1500)
  
  # Bigger win should result in bigger ELO change
  expect_true(big_change > small_change)
})