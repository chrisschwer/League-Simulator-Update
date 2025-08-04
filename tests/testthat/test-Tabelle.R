library(testthat)
source("../../RCode/Tabelle.R")
source("../../RCode/Tabelle_presentation.R")

test_that("Tabelle calculates points correctly", {
  # Create a completed season
  season <- create_completed_season()
  
  # No adjustments
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle_presentation(
    season = season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Check structure
  expect_equal(nrow(result), 4)
  expect_equal(ncol(result), 10)
  expect_equal(colnames(result), c("Pl", "Team", "GP", "W", "D", "L", "Pts", "GF", "GA", "GD"))
  
  # Check that all teams are represented
  expect_equal(sort(result[, "Team"]), 1:4)
  
  # Check points calculation (3 for win, 1 for draw)
  for (i in 1:4) {
    expect_equal(
      result[i, "Pts"],
      result[i, "W"] * 3 + result[i, "D"] * 1
    )
  }
  
  # Check goal difference
  for (i in 1:4) {
    expect_equal(
      result[i, "GD"],
      result[i, "GF"] - result[i, "GA"]
    )
  }
})

test_that("Tabelle sorts teams correctly", {
  # Create a specific season to test sorting
  season <- matrix(c(
    1, 2, 3, 0,  # Team 1 beats Team 2 3-0
    3, 4, 2, 1,  # Team 3 beats Team 4 2-1
    1, 3, 1, 1,  # Team 1 draws Team 3 1-1
    2, 4, 2, 2,  # Team 2 draws Team 4 2-2
    1, 4, 2, 0,  # Team 1 beats Team 4 2-0
    2, 3, 0, 1   # Team 3 beats Team 2 1-0
  ), nrow = 6, byrow = TRUE)
  
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle_presentation(
    season = season,
    numberTeams = 4,
    numberGames = 6,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Teams should be sorted by points (descending)
  for (i in 1:(nrow(result) - 1)) {
    expect_true(result[i, "Pts"] >= result[i + 1, "Pts"])
  }
  
  # Check position column
  expect_equal(result[, "Pl"], 1:4)
})

test_that("Tabelle handles point adjustments", {
  season <- create_completed_season()
  
  # Apply point adjustments
  adj_points <- create_test_adjustments(4, "points")  # Team 1: -6, Team 3: +3
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle_presentation(
    season = season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = adj_points,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Calculate expected points manually for verification
  result_no_adj <- Tabelle_presentation(
    season = season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Find teams in adjusted table
  team1_row <- which(result[, "Team"] == 1)
  team3_row <- which(result[, "Team"] == 3)
  
  # Find same teams in unadjusted table
  team1_row_no_adj <- which(result_no_adj[, "Team"] == 1)
  team3_row_no_adj <- which(result_no_adj[, "Team"] == 3)
  
  # Check adjustments were applied
  expect_equal(
    result[team1_row, "Pts"],
    result_no_adj[team1_row_no_adj, "Pts"] - 6
  )
  expect_equal(
    result[team3_row, "Pts"],
    result_no_adj[team3_row_no_adj, "Pts"] + 3
  )
})

test_that("Tabelle handles empty season", {
  # Season with no games played
  season <- create_test_season(0)
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle_presentation(
    season = season,
    numberTeams = 4,
    numberGames = 0,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # All teams should have 0 games, 0 points, etc.
  expect_true(all(result[, "GP"] == 0))
  expect_true(all(result[, "W"] == 0))
  expect_true(all(result[, "D"] == 0))
  expect_true(all(result[, "L"] == 0))
  expect_true(all(result[, "Pts"] == 0))
})

test_that("Tabelle handles tie-breaking correctly", {
  # Create a season where teams have same points but different goal differences
  season <- matrix(c(
    1, 2, 2, 1,  # Team 1 beats Team 2 2-1
    3, 4, 3, 0,  # Team 3 beats Team 4 3-0
    1, 3, 0, 0,  # Team 1 draws Team 3 0-0
    2, 4, 1, 1,  # Team 2 draws Team 4 1-1
    1, 4, 1, 1,  # Team 1 draws Team 4 1-1
    2, 3, 1, 2   # Team 3 beats Team 2 2-1
  ), nrow = 6, byrow = TRUE)
  
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle_presentation(
    season = season,
    numberTeams = 4,
    numberGames = 6,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # When points are equal, teams should be sorted by goal difference
  for (i in 1:(nrow(result) - 1)) {
    if (result[i, "Pts"] == result[i + 1, "Pts"]) {
      expect_true(result[i, "GD"] >= result[i + 1, "GD"])
    }
  }
})