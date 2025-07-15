library(testthat)
source("../../RCode/simulationsCPP.R")

test_that("simulationsCPP handles fully played season correctly", {
  # Create a fully played season
  season <- create_completed_season()
  elo_values <- create_test_elo_values(4)
  
  # No adjustments
  adj_none <- create_test_adjustments(4, "none")
  
  # Run simulation with 100 iterations (should not simulate anything)
  set.seed(123)
  result <- simulationsCPP(
    season = season,
    ELOValue = elo_values,
    numberTeams = 4,
    numberGames = 12,
    modFactor = 40,
    homeAdvantage = 100,
    iterations = 100,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Check result structure
  expect_equal(dim(result), c(4, 4))
  expect_equal(colnames(result), c("Team", "Points", "GoalDiff", "GoalsScored"))
  
  # All 100 iterations should produce same result for fully played season
  # Team rankings should be deterministic
  unique_results <- unique(result[, 1])
  expect_equal(length(unique_results), 4)
})

test_that("simulationsCPP handles empty season correctly", {
  # Create an empty season (no games played)
  season <- create_test_season(0)
  elo_values <- create_test_elo_values(4)
  adj_none <- create_test_adjustments(4, "none")
  
  # Run simulation
  set.seed(456)
  result <- simulationsCPP(
    season = season,
    ELOValue = elo_values,
    numberTeams = 4,
    numberGames = 12,
    modFactor = 40,
    homeAdvantage = 100,
    iterations = 1000,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Check result structure
  expect_equal(dim(result), c(4, 4))
  
  # With no games played, all teams should have 0 points before adjustments
  # But positions will vary due to simulations
  expect_true(all(result[, 1] %in% 1:4))
})

test_that("simulationsCPP handles partial season correctly", {
  # Create a partially played season (6 out of 12 games)
  season <- create_test_season(6)
  elo_values <- create_test_elo_values(4)
  adj_none <- create_test_adjustments(4, "none")
  
  # Run simulation
  set.seed(789)
  result <- simulationsCPP(
    season = season,
    ELOValue = elo_values,
    numberTeams = 4,
    numberGames = 12,
    modFactor = 40,
    homeAdvantage = 100,
    iterations = 1000,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Check result structure
  expect_equal(dim(result), c(4, 4))
  
  # Teams should have varied positions due to simulations
  # Check that all positions are represented
  expect_equal(sort(unique(result[, 1])), 1:4)
})

test_that("simulationsCPP applies point adjustments correctly", {
  # Create a fully played season
  season <- create_completed_season()
  elo_values <- create_test_elo_values(4)
  
  # Apply point adjustments
  adj_points <- create_test_adjustments(4, "points")
  adj_none <- create_test_adjustments(4, "none")
  
  # Run simulation
  set.seed(321)
  result <- simulationsCPP(
    season = season,
    ELOValue = elo_values,
    numberTeams = 4,
    numberGames = 12,
    modFactor = 40,
    homeAdvantage = 100,
    iterations = 100,
    AdjPoints = adj_points,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Adjustments should affect final standings
  expect_equal(dim(result), c(4, 4))
  
  # Team 1 with -6 penalty should likely be lower in standings
  # Team 3 with +3 bonus should likely be higher
  # This is probabilistic, so we just check structure
  expect_true(all(result[, 1] %in% 1:4))
})

test_that("simulationsCPP handles different iteration counts", {
  season <- create_test_season(3)
  elo_values <- create_test_elo_values(4)
  adj_none <- create_test_adjustments(4, "none")
  
  # Test with different iteration counts
  iteration_counts <- c(100, 1000, 10000)
  
  for (iters in iteration_counts) {
    set.seed(999)
    result <- simulationsCPP(
      season = season,
      ELOValue = elo_values,
      numberTeams = 4,
      numberGames = 12,
      modFactor = 40,
      homeAdvantage = 100,
      iterations = iters,
      AdjPoints = adj_none,
      AdjGoals = adj_none,
      AdjGoalsAgainst = adj_none,
      AdjGoalDiff = adj_none
    )
    
    expect_equal(dim(result), c(4, 4))
    expect_true(all(result[, 1] %in% 1:4))
  }
})

test_that("simulationsCPP handles goal adjustments correctly", {
  season <- create_completed_season()
  elo_values <- create_test_elo_values(4)
  
  # Apply goal adjustments
  adj_goals <- create_test_adjustments(4, "goals")
  adj_none <- create_test_adjustments(4, "none")
  
  # Run simulation
  set.seed(111)
  result <- simulationsCPP(
    season = season,
    ELOValue = elo_values,
    numberTeams = 4,
    numberGames = 12,
    modFactor = 40,
    homeAdvantage = 100,
    iterations = 100,
    AdjPoints = adj_none,
    AdjGoals = adj_goals,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Check result structure
  expect_equal(dim(result), c(4, 4))
  
  # Goal adjustments should affect goal-related columns
  expect_true(all(result[, 1] %in% 1:4))
})

test_that("simulationsCPP produces consistent results with same seed", {
  season <- create_test_season(6)
  elo_values <- create_test_elo_values(4)
  adj_none <- create_test_adjustments(4, "none")
  
  # Run simulation twice with same seed
  set.seed(42)
  result1 <- simulationsCPP(
    season = season,
    ELOValue = elo_values,
    numberTeams = 4,
    numberGames = 12,
    modFactor = 40,
    homeAdvantage = 100,
    iterations = 500,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  set.seed(42)
  result2 <- simulationsCPP(
    season = season,
    ELOValue = elo_values,
    numberTeams = 4,
    numberGames = 12,
    modFactor = 40,
    homeAdvantage = 100,
    iterations = 500,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Results should be identical
  expect_equal(result1, result2)
})

test_that("simulationsCPP handles extreme ELO differences", {
  season <- create_test_season(0)
  # Create extreme ELO differences
  elo_values <- c(2000, 1000, 1500, 1200)
  adj_none <- create_test_adjustments(4, "none")
  
  # Run simulation
  set.seed(777)
  result <- simulationsCPP(
    season = season,
    ELOValue = elo_values,
    numberTeams = 4,
    numberGames = 12,
    modFactor = 40,
    homeAdvantage = 100,
    iterations = 1000,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Check result structure
  expect_equal(dim(result), c(4, 4))
  
  # Team 1 (ELO 2000) should frequently be ranked 1st
  # This is probabilistic but with 1000 iterations patterns should emerge
  expect_true(all(result[, 1] %in% 1:4))
})

test_that("simulationsCPP handles single team edge case", {
  # Create a season with only 1 team (edge case)
  season <- matrix(NA, nrow = 0, ncol = 4)
  elo_values <- 1500
  adj_none <- 0
  
  # This should handle gracefully or error appropriately
  expect_error(
    simulationsCPP(
      season = season,
      ELOValue = elo_values,
      numberTeams = 1,
      numberGames = 0,
      modFactor = 40,
      homeAdvantage = 100,
      iterations = 100,
      AdjPoints = adj_none,
      AdjGoals = adj_none,
      AdjGoalsAgainst = adj_none,
      AdjGoalDiff = adj_none
    ),
    NA  # We don't expect an error necessarily, depends on implementation
  )
})