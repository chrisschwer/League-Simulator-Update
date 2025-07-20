# Debug goal adjustments only test

source("RCode/Tabelle.R")
source("tests/testthat/helper-fixtures.R")

season <- create_completed_season()
adj_goals <- create_test_adjustments(4, "goals")  # c(2, -1, 0, 1)
adj_none <- rep(0, 4)

print("Goal adjustments:")
print(adj_goals)

# Base result without adjustments
result_no_adj <- Tabelle(
  season = season,
  numberTeams = 4,
  numberGames = 12,
  AdjPoints = adj_none,
  AdjGoals = adj_none,
  AdjGoalsAgainst = adj_none,
  AdjGoalDiff = adj_none
)

print("\nBase table without adjustments (team, rank, GF, GA, GD, Pts):")
print(result_no_adj)

# Result with goal adjustments only
result <- Tabelle(
  season = season,
  numberTeams = 4,
  numberGames = 12,
  AdjPoints = adj_none,
  AdjGoals = adj_goals,
  AdjGoalsAgainst = adj_none,
  AdjGoalDiff = adj_none
)

print("\nTable with goal adjustments:")
print(result)

print("\nChecking goal difference calculation:")
for (i in 1:4) {
  base_gd <- result_no_adj[i, 5]
  actual_gd <- result[i, 5]
  actual_gf <- result[i, 3]
  actual_ga <- result[i, 4]
  calc_gd <- actual_gf - actual_ga
  
  print(paste("Team", i, ": base GD =", base_gd, 
              ", actual GD =", actual_gd,
              ", GF - GA =", calc_gd,
              ", adj_goals =", adj_goals[i]))
}