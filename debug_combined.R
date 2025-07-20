# Debug combined adjustments test

source("RCode/Tabelle.R")
source("RCode/Tabelle_presentation.R")
source("tests/testthat/helper-fixtures.R")

# Test with combined adjustments
season <- create_completed_season()
adj_points <- create_test_adjustments(4, "points")
adj_goals <- create_test_adjustments(4, "goals")
adj_goals_against <- create_test_adjustments(4, "goals_against")
adj_goal_diff <- create_test_adjustments(4, "goal_diff")

print("Adjustments:")
print(paste("adj_points:", paste(adj_points, collapse=", ")))
print(paste("adj_goals:", paste(adj_goals, collapse=", ")))
print(paste("adj_goals_against:", paste(adj_goals_against, collapse=", ")))
print(paste("adj_goal_diff:", paste(adj_goal_diff, collapse=", ")))

# Get base result without adjustments
base_no_adj <- Tabelle(
  season = season,
  numberTeams = 4,
  numberGames = 12,
  AdjPoints = rep(0, 4),
  AdjGoals = rep(0, 4),
  AdjGoalsAgainst = rep(0, 4),
  AdjGoalDiff = rep(0, 4)
)

print("\nBase table without adjustments (columns: team, rank, GF, GA, GD, Pts):")
print(base_no_adj)

# Get base result with adjustments
base_with_adj <- Tabelle(
  season = season,
  numberTeams = 4,
  numberGames = 12,
  AdjPoints = adj_points,
  AdjGoals = adj_goals,
  AdjGoalsAgainst = adj_goals_against,
  AdjGoalDiff = adj_goal_diff
)

print("\nBase table with adjustments:")
print(base_with_adj)

# Calculate expected goal differences according to test
print("\nExpected goal differences according to test formula:")
for (team in 1:4) {
  base_gd <- base_no_adj[team, 5]  # GD column
  expected_gd <- base_gd + adj_goals[team] - adj_goals_against[team] + adj_goal_diff[team]
  actual_gd <- base_with_adj[team, 5]
  print(paste("Team", team, ": base GD =", base_gd, 
              ", expected =", expected_gd,
              ", actual =", actual_gd,
              ", match =", expected_gd == actual_gd))
}