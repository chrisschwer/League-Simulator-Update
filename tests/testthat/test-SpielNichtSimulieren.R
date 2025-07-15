library(testthat)
# Load the Rcpp exported function
source("../../RCode/RcppExports.R")

test_that("SpielNichtSimulieren calculates ELO changes correctly for home win", {
  # Home team wins 2-1
  result <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 2,
    GoalsAway = 1,
    modFactor = 40,
    homeAdvantage = 0  # Already included in ELOHome by SpielCPP
  )
  
  # Result should have 5 elements
  expect_length(result, 5)
  
  # Extract values
  new_elo_home <- result[1]
  new_elo_away <- result[2]
  goals_home <- result[3]
  goals_away <- result[4]
  win_prob_home <- result[5]
  
  # Check goals are returned correctly
  expect_equal(goals_home, 2)
  expect_equal(goals_away, 1)
  
  # Home won, so ELO should increase
  expect_true(new_elo_home > 1500)
  expect_true(new_elo_away < 1500)
  
  # ELO changes should sum to zero
  expect_equal(
    (new_elo_home - 1500) + (new_elo_away - 1500),
    0,
    tolerance = 0.001
  )
  
  # Win probability should be around 0.5 for equal teams
  expect_true(win_prob_home > 0.4 && win_prob_home < 0.6)
})

test_that("SpielNichtSimulieren handles draws correctly", {
  # Draw 1-1
  result <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 1,
    GoalsAway = 1,
    modFactor = 40,
    homeAdvantage = 0
  )
  
  new_elo_home <- result[1]
  new_elo_away <- result[2]
  
  # For equal teams with a draw, ELO changes should be minimal
  expect_true(abs(new_elo_home - 1500) < 5)
  expect_true(abs(new_elo_away - 1500) < 5)
  
  # ELO changes should still sum to zero
  expect_equal(
    (new_elo_home - 1500) + (new_elo_away - 1500),
    0,
    tolerance = 0.001
  )
})

test_that("SpielNichtSimulieren handles upsets correctly", {
  # Weak team beats strong team
  result <- SpielNichtSimulieren(
    ELOHome = 1700,  # Strong team
    ELOAway = 1300,  # Weak team
    GoalsHome = 0,
    GoalsAway = 1,
    modFactor = 40,
    homeAdvantage = 0
  )
  
  new_elo_home <- result[1]
  new_elo_away <- result[2]
  win_prob_home <- result[5]
  
  # Strong team lost, so should lose significant ELO
  expect_true(new_elo_home < 1700)
  expect_true(new_elo_away > 1300)
  
  # Changes should be substantial due to upset
  expect_true(abs(new_elo_home - 1700) > 20)
  expect_true(abs(new_elo_away - 1300) > 20)
  
  # Win probability should have favored home team
  expect_true(win_prob_home > 0.7)
})

test_that("SpielNichtSimulieren applies goal difference modifier", {
  # Test different goal differences
  # 1-0 win
  result_small <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 1,
    GoalsAway = 0,
    modFactor = 40,
    homeAdvantage = 0
  )
  
  # 4-0 win
  result_large <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 4,
    GoalsAway = 0,
    modFactor = 40,
    homeAdvantage = 0
  )
  
  # Larger goal difference should result in larger ELO change
  elo_change_small <- abs(result_small[1] - 1500)
  elo_change_large <- abs(result_large[1] - 1500)
  
  expect_true(elo_change_large > elo_change_small)
})

test_that("SpielNichtSimulieren respects ELO change limits", {
  # Extreme ELO difference with large goal difference
  result <- SpielNichtSimulieren(
    ELOHome = 2000,  # Very strong team
    ELOAway = 1000,  # Very weak team
    GoalsHome = 10,  # Huge win
    GoalsAway = 0,
    modFactor = 40,
    homeAdvantage = 0
  )
  
  new_elo_home <- result[1]
  new_elo_away <- result[2]
  
  # Even with extreme conditions, ELO change should be capped
  # The C++ code limits delta to [-400, 400]
  elo_change_home <- new_elo_home - 2000
  elo_change_away <- new_elo_away - 1000
  
  # Changes should be within reasonable bounds
  expect_true(abs(elo_change_home) <= 400)
  expect_true(abs(elo_change_away) <= 400)
  
  # Should still sum to zero
  expect_equal(elo_change_home + elo_change_away, 0, tolerance = 0.001)
})

test_that("SpielNichtSimulieren calculates win probability correctly", {
  # Test various ELO differences
  test_cases <- list(
    list(home = 1500, away = 1500, expected_range = c(0.45, 0.55)),
    list(home = 1600, away = 1400, expected_range = c(0.70, 0.80)),
    list(home = 1400, away = 1600, expected_range = c(0.20, 0.30)),
    list(home = 1800, away = 1200, expected_range = c(0.90, 0.99))
  )
  
  for (test in test_cases) {
    result <- SpielNichtSimulieren(
      ELOHome = test$home,
      ELOAway = test$away,
      GoalsHome = 1,
      GoalsAway = 1,
      modFactor = 40,
      homeAdvantage = 0
    )
    
    win_prob <- result[5]
    expect_true(
      win_prob >= test$expected_range[1] && win_prob <= test$expected_range[2],
      info = paste("ELO", test$home, "vs", test$away, "gave probability", win_prob)
    )
  }
})

test_that("SpielNichtSimulieren handles different mod factors", {
  # Test with different K factors
  mod_factors <- c(20, 40, 60)
  
  for (k in mod_factors) {
    result <- SpielNichtSimulieren(
      ELOHome = 1500,
      ELOAway = 1400,
      GoalsHome = 2,
      GoalsAway = 1,
      modFactor = k,
      homeAdvantage = 0
    )
    
    elo_change <- abs(result[1] - 1500)
    
    # Higher K factor should lead to larger changes
    if (k == 20) {
      expect_true(elo_change < 20)
    } else if (k == 60) {
      expect_true(elo_change > 15)
    }
  }
})

test_that("SpielNichtSimulieren handles 0-0 draws", {
  result <- SpielNichtSimulieren(
    ELOHome = 1550,
    ELOAway = 1450,
    GoalsHome = 0,
    GoalsAway = 0,
    modFactor = 40,
    homeAdvantage = 0
  )
  
  # Should handle 0-0 without errors
  expect_length(result, 5)
  expect_equal(result[3], 0)
  expect_equal(result[4], 0)
  
  # Favorite (home) should lose some ELO for drawing
  expect_true(result[1] < 1550)
  expect_true(result[2] > 1450)
})

test_that("SpielNichtSimulieren maintains ELO conservation", {
  # Test multiple scenarios to ensure ELO is always conserved
  scenarios <- list(
    list(home = 1500, away = 1500, goals_h = 3, goals_a = 0),
    list(home = 1600, away = 1400, goals_h = 1, goals_a = 1),
    list(home = 1300, away = 1700, goals_h = 2, goals_a = 1),
    list(home = 1450, away = 1550, goals_h = 0, goals_a = 5)
  )
  
  for (scenario in scenarios) {
    result <- SpielNichtSimulieren(
      ELOHome = scenario$home,
      ELOAway = scenario$away,
      GoalsHome = scenario$goals_h,
      GoalsAway = scenario$goals_a,
      modFactor = 40,
      homeAdvantage = 0
    )
    
    total_elo_before <- scenario$home + scenario$away
    total_elo_after <- result[1] + result[2]
    
    expect_equal(
      total_elo_after,
      total_elo_before,
      tolerance = 0.001,
      info = paste("Scenario:", scenario$home, "vs", scenario$away,
                   "Result:", scenario$goals_h, "-", scenario$goals_a)
    )
  }
})

test_that("SpielNichtSimulieren handles edge case scores", {
  # Very high scoring game
  result <- SpielNichtSimulieren(
    ELOHome = 1500,
    ELOAway = 1500,
    GoalsHome = 8,
    GoalsAway = 7,
    modFactor = 40,
    homeAdvantage = 0
  )
  
  # Should handle high scores
  expect_length(result, 5)
  expect_equal(result[3], 8)
  expect_equal(result[4], 7)
  
  # Close high-scoring game, home wins by 1
  expect_true(result[1] > 1500)
  expect_true(result[2] < 1500)
})