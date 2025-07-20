# Check if GD = GF - GA in adjusted table

source("RCode/Tabelle.R")
source("tests/testthat/helper-fixtures.R")

season <- create_completed_season()
adj_points <- create_test_adjustments(4, "points")
adj_goals <- create_test_adjustments(4, "goals")
adj_goals_against <- create_test_adjustments(4, "goals_against")
adj_goal_diff <- create_test_adjustments(4, "goal_diff")

result <- Tabelle(
  season = season,
  numberTeams = 4,
  numberGames = 12,
  AdjPoints = adj_points,
  AdjGoals = adj_goals,
  AdjGoalsAgainst = adj_goals_against,
  AdjGoalDiff = adj_goal_diff
)

print("Checking GD consistency:")
print("Team | GF | GA | GD | GF-GA | Match?")
for (i in 1:4) {
  gf <- result[i, 3]
  ga <- result[i, 4]
  gd <- result[i, 5]
  calculated_gd <- gf - ga
  print(paste(result[i, 1], "|", gf, "|", ga, "|", gd, "|", calculated_gd, "|", gd == calculated_gd))
}