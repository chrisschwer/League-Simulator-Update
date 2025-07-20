# Debug empty season

source("RCode/Tabelle.R")
source("RCode/Tabelle_presentation.R")
source("tests/testthat/helper-fixtures.R")

season <- create_test_season(0)
adj_none <- create_test_adjustments(4, "none")

print("Empty season:")
print(head(season))

print("\nAdjustments (should be all zeros):")
print(adj_none)

result <- Tabelle_presentation(
  season = season,
  numberTeams = 4,
  numberGames = 12,
  AdjPoints = adj_none,
  AdjGoals = adj_none,
  AdjGoalsAgainst = adj_none,
  AdjGoalDiff = adj_none
)

print("\nResult:")
print(result)