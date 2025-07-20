# Debug base Tabelle with empty season

source("RCode/Tabelle.R")
source("tests/testthat/helper-fixtures.R")

# Create truly empty season
empty_season <- matrix(numeric(0), nrow = 0, ncol = 4)

print("Empty season matrix:")
print(empty_season)
print(paste("Dimensions:", nrow(empty_season), "x", ncol(empty_season)))

result <- Tabelle(
  season = empty_season,
  numberTeams = 4,
  numberGames = 0,
  AdjPoints = rep(0, 4),
  AdjGoals = rep(0, 4),
  AdjGoalsAgainst = rep(0, 4),
  AdjGoalDiff = rep(0, 4)
)

print("\nBase Tabelle result:")
print(result)