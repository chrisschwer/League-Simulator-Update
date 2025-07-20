# Debug test to understand goal difference handling

source("RCode/Tabelle.R")
source("RCode/Tabelle_presentation.R")
source("tests/testthat/helper-fixtures.R")

# Test with goal adjustments
season <- create_completed_season()
adj_goals <- create_test_adjustments(4, "goals")  # Team 1: -5, Team 2: +3

# Get base table
base_result <- Tabelle(
  season = season,
  numberTeams = 4,
  numberGames = 12,
  AdjPoints = rep(0, 4),
  AdjGoals = adj_goals,
  AdjGoalsAgainst = rep(0, 4),
  AdjGoalDiff = rep(0, 4)
)

print("Base table result (columns: team, rank, GF, GA, GD, Pts):")
print(base_result)

# Test with combined adjustments
adj_points <- create_test_adjustments(4, "points")
adj_goals <- create_test_adjustments(4, "goals")
adj_goals_against <- create_test_adjustments(4, "goals_against")
adj_goal_diff <- create_test_adjustments(4, "goal_diff")

print("\nAdjustments:")
print(paste("adj_points:", paste(adj_points, collapse=", ")))
print(paste("adj_goals:", paste(adj_goals, collapse=", ")))
print(paste("adj_goals_against:", paste(adj_goals_against, collapse=", ")))
print(paste("adj_goal_diff:", paste(adj_goal_diff, collapse=", ")))

base_combined <- Tabelle(
  season = season,
  numberTeams = 4,
  numberGames = 12,
  AdjPoints = adj_points,
  AdjGoals = adj_goals,
  AdjGoalsAgainst = adj_goals_against,
  AdjGoalDiff = adj_goal_diff
)

print("\nBase table with combined adjustments:")
print(base_combined)

# Now test presentation
pres_result <- Tabelle_presentation(
  season = season,
  numberTeams = 4,
  numberGames = 12,
  AdjPoints = adj_points,
  AdjGoals = adj_goals,
  AdjGoalsAgainst = adj_goals_against,
  AdjGoalDiff = adj_goal_diff
)

print("\nPresentation result:")
print(pres_result)