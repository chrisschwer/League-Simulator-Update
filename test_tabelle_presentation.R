# Test script for Tabelle_presentation function

# Source required files
source("RCode/Tabelle.R")
source("RCode/Tabelle_presentation.R")

# Create test data - simple 2-team league with 2 games
season <- matrix(c(
  1, 2, 2, 1,  # Team 1 beats Team 2 2-1
  2, 1, 1, 1   # Draw 1-1
), nrow = 2, byrow = TRUE)

# Test without adjustments
result <- Tabelle_presentation(
  season = season,
  numberTeams = 2,
  numberGames = 2,
  AdjPoints = c(0, 0),
  AdjGoals = c(0, 0),
  AdjGoalsAgainst = c(0, 0),
  AdjGoalDiff = c(0, 0)
)

# Print results
print("Test Results:")
print(result)

# Check structure
cat("\nStructure checks:\n")
cat("Number of rows:", nrow(result), "\n")
cat("Number of columns:", ncol(result), "\n")
cat("Column names:", paste(colnames(result), collapse = ", "), "\n")

# Check specific values
cat("\nValue checks:\n")
cat("Team 1 - W:", result[result$Team == 1, "W"], "D:", result[result$Team == 1, "D"], "L:", result[result$Team == 1, "L"], "\n")
cat("Team 2 - W:", result[result$Team == 2, "W"], "D:", result[result$Team == 2, "D"], "L:", result[result$Team == 2, "L"], "\n")
cat("Team 1 - Points:", result[result$Team == 1, "Pts"], "\n")
cat("Team 2 - Points:", result[result$Team == 2, "Pts"], "\n")

# Test with empty season
cat("\n\nTest with empty season:\n")
empty_season <- matrix(numeric(0), nrow = 0, ncol = 4)
result_empty <- Tabelle_presentation(
  season = empty_season,
  numberTeams = 2,
  numberGames = 0,
  AdjPoints = c(0, 0),
  AdjGoals = c(0, 0),
  AdjGoalsAgainst = c(0, 0),
  AdjGoalDiff = c(0, 0)
)
print(result_empty)