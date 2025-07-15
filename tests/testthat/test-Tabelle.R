library(testthat)
source("../../RCode/Tabelle.R")

test_that("Tabelle calculates points correctly", {
  # Create a completed season
  season <- create_completed_season()
  
  # No adjustments
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle(
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
  
  # Check games played
  expect_true(all(result[, "GP"] > 0))
  
  # Check that W + D + L = GP for each team
  for (i in 1:4) {
    expect_equal(
      result[i, "W"] + result[i, "D"] + result[i, "L"],
      result[i, "GP"]
    )
  }
  
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
  
  result <- Tabelle(
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
  
  result <- Tabelle(
    season = season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = adj_points,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Calculate expected points manually for verification
  result_no_adj <- Tabelle(
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

test_that("Tabelle handles goal adjustments", {
  season <- create_completed_season()
  
  # Apply goal adjustments
  adj_goals <- create_test_adjustments(4, "goals")  # Various goal adjustments
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle(
    season = season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = adj_none,
    AdjGoals = adj_goals,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Get unadjusted result for comparison
  result_no_adj <- Tabelle(
    season = season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Check that goal adjustments were applied
  for (team in 1:4) {
    team_row <- which(result[, "Team"] == team)
    team_row_no_adj <- which(result_no_adj[, "Team"] == team)
    
    expected_gf <- result_no_adj[team_row_no_adj, "GF"] + adj_goals[team]
    expect_equal(result[team_row, "GF"], expected_gf)
    
    # Goal difference should be updated accordingly
    expected_gd <- result[team_row, "GF"] - result[team_row, "GA"]
    expect_equal(result[team_row, "GD"], expected_gd)
  }
})

test_that("Tabelle handles empty season", {
  # Season with no games played
  season <- create_test_season(0)
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle(
    season = season,
    numberTeams = 4,
    numberGames = 12,
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
  expect_true(all(result[, "GF"] == 0))
  expect_true(all(result[, "GA"] == 0))
  expect_true(all(result[, "GD"] == 0))
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
  
  result <- Tabelle(
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
      
      # If goal difference is also equal, sort by goals scored
      if (result[i, "GD"] == result[i + 1, "GD"]) {
        expect_true(result[i, "GF"] >= result[i + 1, "GF"])
      }
    }
  }
})

test_that("Tabelle handles partial season correctly", {
  # Season with some games played
  season <- create_test_season(6)
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle(
    season = season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Only count played games
  total_games_played <- sum(result[, "GP"])
  expect_equal(total_games_played, 12)  # 6 games * 2 teams per game
  
  # Each team should have played some games
  expect_true(all(result[, "GP"] > 0))
})

test_that("Tabelle handles all teams with same points", {
  # Create a season where all games are draws
  season <- matrix(c(
    1, 2, 1, 1,
    3, 4, 0, 0,
    1, 3, 2, 2,
    2, 4, 1, 1,
    1, 4, 0, 0,
    2, 3, 2, 2
  ), nrow = 6, byrow = TRUE)
  
  adj_none <- create_test_adjustments(4, "none")
  
  result <- Tabelle(
    season = season,
    numberTeams = 4,
    numberGames = 6,
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # All teams should have same points (all draws)
  expect_true(all(result[, "Pts"] == result[1, "Pts"]))
  
  # Tie-breaking by goal difference and goals scored should still apply
  expect_equal(result[, "Pl"], 1:4)
})

test_that("Tabelle handles combined adjustments", {
  season <- create_completed_season()
  
  # Apply multiple adjustments
  adj_points <- c(-3, 0, 6, 0)
  adj_goals <- c(2, -1, 0, 1)
  adj_goals_against <- c(0, 2, -1, 0)
  adj_goal_diff <- c(1, 0, -2, 3)
  
  result <- Tabelle(
    season = season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = adj_points,
    AdjGoals = adj_goals,
    AdjGoalsAgainst = adj_goals_against,
    AdjGoalDiff = adj_goal_diff
  )
  
  # Get base result for comparison
  result_no_adj <- Tabelle(
    season = season,
    numberTeams = 4,
    numberGames = 12,
    AdjPoints = create_test_adjustments(4, "none"),
    AdjGoals = create_test_adjustments(4, "none"),
    AdjGoalsAgainst = create_test_adjustments(4, "none"),
    AdjGoalDiff = create_test_adjustments(4, "none")
  )
  
  # Verify adjustments for each team
  for (team in 1:4) {
    team_row <- which(result[, "Team"] == team)
    team_row_no_adj <- which(result_no_adj[, "Team"] == team)
    
    # Points adjustment
    expect_equal(
      result[team_row, "Pts"],
      result_no_adj[team_row_no_adj, "Pts"] + adj_points[team]
    )
    
    # Goals for adjustment
    expect_equal(
      result[team_row, "GF"],
      result_no_adj[team_row_no_adj, "GF"] + adj_goals[team]
    )
    
    # Goals against adjustment
    expect_equal(
      result[team_row, "GA"],
      result_no_adj[team_row_no_adj, "GA"] + adj_goals_against[team]
    )
    
    # Goal difference should include all adjustments
    expected_gd <- result_no_adj[team_row_no_adj, "GD"] + 
                   adj_goals[team] - adj_goals_against[team] + adj_goal_diff[team]
    expect_equal(result[team_row, "GD"], expected_gd)
  }
})