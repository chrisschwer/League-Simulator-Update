# Simple Integration Tests for End-to-End Simulation

library(testthat)
source("../../RCode/SaisonSimulierenCPP.R")
source("../../RCode/SpielCPP.R")
source("../../RCode/RcppExports.R")
source("../../RCode/Tabelle.R")
source("../../RCode/simulationsCPP.R")
source("../../RCode/cpp_wrappers.R")

# Source helper files
source("test-helpers/elo-mock-generator.R")
source("helper-fixtures.R")

test_that("Can simulate a complete season end-to-end", {
  # Create teams with ELO values
  elo_values <- c(1600, 1550, 1450, 1400)  # 4 teams with different strengths
  
  # Create empty season schedule
  season <- create_test_season(0)  # 12 games for 4 teams
  
  # Simulate the season
  set.seed(123)
  result <- SaisonSimulierenCPP(
    Spielplan = season,
    ELOWerte = elo_values,
    ModFaktor = 40,
    Heimvorteil = 100,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  simulated_season <- result[[1]]
  final_elos <- result[[2]]
  
  # Check all games have results
  expect_false(any(is.na(simulated_season[, 3])))
  expect_false(any(is.na(simulated_season[, 4])))
  
  # Check ELO values changed
  expect_false(all(final_elos == elo_values))
  
  # Create table from results
  adj_none <- rep(0, 4)
  table <- Tabelle(
    season = simulated_season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Verify table is correct
  expect_equal(nrow(table), 4)
  expect_equal(sum(table[, "GP"]), 24)  # Each team plays 6 games
})

test_that("Monte Carlo simulations produce stable probability estimates", {
  # Setup
  elo_values <- c(1700, 1600, 1500, 1400)
  season <- create_test_season(6)  # Half completed
  adj_none <- rep(0, 4)
  
  # Run simulations
  set.seed(456)
  result <- simulationsCPP_wrapper(
    season = season,
    ELOValue = elo_values,
    numberTeams = 4,
    numberGames = 12,
    modFactor = 40,
    homeAdvantage = 100,
    iterations = 1000,  # Reduced for test speed
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Check result structure
  expect_equal(ncol(result), 4)
  expect_equal(colnames(result), c("Team", "Points", "GoalDiff", "GoalsScored"))
  
  # Stronger team should have more points on average
  team_points <- result[, "Points"]
  names(team_points) <- result[, "Team"]
  expect_true(team_points["1"] > team_points["4"])  # Best team beats worst
})

test_that("ELO calculations are consistent between R and C++", {
  # Test parameters
  elo_home <- 1600
  elo_away <- 1400
  goals_home <- 2
  goals_away <- 1
  mod_factor <- 40
  home_advantage <- 100
  
  # Call C++ function via wrapper
  result <- SpielNichtSimulieren(
    ELOHome = elo_home,
    ELOAway = elo_away,
    GoalsHome = goals_home,
    GoalsAway = goals_away,
    ModFaktor = mod_factor,
    Heimvorteil = home_advantage
  )
  
  # Manual calculation
  elo_delta <- elo_home + home_advantage - elo_away
  elo_prob <- 1 / (1 + 10^(-elo_delta/400))
  result_value <- 1  # Home win
  goal_mod <- sqrt(abs(goals_home - goals_away))
  elo_change <- (result_value - elo_prob) * goal_mod * mod_factor
  
  expected_elo_home <- elo_home + elo_change
  expected_elo_away <- elo_away - elo_change
  
  # Compare (allowing small numerical differences)
  expect_equal(result[1], expected_elo_home, tolerance = 0.1)
  expect_equal(result[2], expected_elo_away, tolerance = 0.1)
  expect_equal(result[3], goals_home)
  expect_equal(result[4], goals_away)
})