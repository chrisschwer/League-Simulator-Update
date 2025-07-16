# Edge Case Tests - Extreme Scenarios
# Tests for boundary conditions and extreme cases

library(testthat)

# Source required functions
source("RCode/simulationsCPP.R")
source("RCode/SaisonSimulierenCPP.R")
source("RCode/SpielCPP.R")
source("RCode/Tabelle.R")
library(Rcpp)
sourceCpp("RCode/SpielNichtSimulieren.cpp")

context("Extreme Scenarios and Edge Cases")

# Helper functions
create_edge_case_season <- function(n_teams, scenario = "normal") {
  if (scenario == "all_complete") {
    # All games have been played
    fixtures <- expand.grid(HomeTeam = 1:n_teams, AwayTeam = 1:n_teams)
    fixtures <- fixtures[fixtures$HomeTeam != fixtures$AwayTeam, ]
    fixtures$HomeGoals <- rpois(nrow(fixtures), 1.5)
    fixtures$AwayGoals <- rpois(nrow(fixtures), 1.2)
  } else if (scenario == "none_played") {
    # No games have been played
    fixtures <- expand.grid(HomeTeam = 1:n_teams, AwayTeam = 1:n_teams)
    fixtures <- fixtures[fixtures$HomeTeam != fixtures$AwayTeam, ]
    fixtures$HomeGoals <- NA
    fixtures$AwayGoals <- NA
  } else if (scenario == "single_game_left") {
    # Only one game remaining
    fixtures <- expand.grid(HomeTeam = 1:n_teams, AwayTeam = 1:n_teams)
    fixtures <- fixtures[fixtures$HomeTeam != fixtures$AwayTeam, ]
    fixtures$HomeGoals <- rpois(nrow(fixtures), 1.5)
    fixtures$AwayGoals <- rpois(nrow(fixtures), 1.2)
    # Set last game to NA
    fixtures$HomeGoals[nrow(fixtures)] <- NA
    fixtures$AwayGoals[nrow(fixtures)] <- NA
  } else {
    # Normal scenario - 50% complete
    fixtures <- expand.grid(HomeTeam = 1:n_teams, AwayTeam = 1:n_teams)
    fixtures <- fixtures[fixtures$HomeTeam != fixtures$AwayTeam, ]
    n_played <- floor(nrow(fixtures) / 2)
    fixtures$HomeGoals <- c(rpois(n_played, 1.5), rep(NA, nrow(fixtures) - n_played))
    fixtures$AwayGoals <- c(rpois(n_played, 1.2), rep(NA, nrow(fixtures) - n_played))
  }
  
  as.matrix(fixtures)
}

test_that("Simulation handles minimum league size (2 teams)", {
  # Create a league with only 2 teams
  season_data <- create_edge_case_season(2, "none_played")
  elo_data <- c("1" = 1500, "2" = 1500)
  
  # Should have exactly 2 games (home and away)
  expect_equal(nrow(season_data), 2)
  
  # Run simulation
  result <- simulationsCPP(
    season = season_data,
    ELOValue = elo_data,
    numberTeams = 2,
    numberGames = 2,
    iterations = 100
  )
  
  # Check result dimensions
  expect_equal(ncol(result), 2)  # 2 teams
  expect_equal(nrow(result), 100)  # 100 iterations
  
  # Each team should finish 1st or 2nd
  expect_true(all(result >= 1 & result <= 2))
})

test_that("Simulation handles completed season correctly", {
  # Season where all games have been played
  season_data <- create_edge_case_season(4, "all_complete")
  elo_data <- c("1" = 1600, "2" = 1500, "3" = 1400, "4" = 1300)
  
  result <- simulationsCPP(
    season = season_data,
    ELOValue = elo_data,
    numberTeams = 4,
    numberGames = nrow(season_data),
    iterations = 50
  )
  
  # All iterations should produce identical results
  # since no games need to be simulated
  for (i in 2:nrow(result)) {
    expect_equal(result[i,], result[1,],
                 info = "Completed season should have deterministic results")
  }
})

test_that("Simulation handles season with no games played", {
  # Fresh season - no games played yet
  season_data <- create_edge_case_season(4, "none_played")
  elo_data <- c("1" = 1500, "2" = 1500, "3" = 1500, "4" = 1500)
  
  result <- simulationsCPP(
    season = season_data,
    ELOValue = elo_data,
    numberTeams = 4,
    numberGames = nrow(season_data),
    iterations = 100
  )
  
  # With equal ELO ratings, each position should be roughly equally likely
  # Check that no team always finishes in the same position
  for (team in 1:4) {
    positions <- result[, team]
    expect_true(length(unique(positions)) > 1,
                info = paste("Team", team, "should have variable positions"))
  }
})

test_that("Extreme ELO differences are handled correctly", {
  # Create extreme ELO differences
  season_data <- create_edge_case_season(4, "none_played")
  elo_data <- c("1" = 2000, "2" = 2000, "3" = 1000, "4" = 1000)  # 1000 point difference
  
  result <- simulationsCPP(
    season = season_data,
    ELOValue = elo_data,
    numberTeams = 4,
    numberGames = nrow(season_data),
    iterations = 100
  )
  
  # Teams 1 and 2 should almost always finish ahead of teams 3 and 4
  team1_positions <- result[, 1]
  team3_positions <- result[, 3]
  
  # At least 90% of the time, team 1 should finish above team 3
  comparisons <- team1_positions < team3_positions
  expect_gt(mean(comparisons), 0.9,
            info = "High ELO team should usually finish above low ELO team")
})

test_that("Table calculation handles edge cases", {
  # Test with minimal data
  minimal_season <- data.frame(
    HomeTeam = c(1, 2),
    AwayTeam = c(2, 1),
    HomeGoals = c(3, 0),
    AwayGoals = c(0, 3)
  )
  
  table_result <- Tabelle(minimal_season, numberTeams = 2, numberGames = 2)
  
  # Both teams should have played 2 games
  expect_equal(nrow(table_result), 2)
  
  # Team 1 won at home, lost away = 3 points
  # Team 2 lost at home, won away = 3 points
  expect_equal(table_result[1, 1], 3)  # Points
  expect_equal(table_result[2, 1], 3)  # Points
  
  # Goal difference should be 0 for both
  expect_equal(table_result[1, 4], 0)  # GD
  expect_equal(table_result[2, 4], 0)  # GD
})

test_that("Single remaining game scenario works correctly", {
  # Season with just one game left
  season_data <- create_edge_case_season(4, "single_game_left")
  elo_data <- c("1" = 1500, "2" = 1500, "3" = 1500, "4" = 1500)
  
  # Count games to simulate
  games_to_sim <- sum(is.na(season_data[,3]))
  expect_equal(games_to_sim, 1)
  
  result <- simulationsCPP(
    season = season_data,
    ELOValue = elo_data,
    numberTeams = 4,
    numberGames = nrow(season_data),
    iterations = 50
  )
  
  # Results should vary but not too much with just one game left
  expect_true(nrow(unique(result)) > 1,
              info = "Results should vary across iterations")
})

test_that("Zero iterations request is handled", {
  season_data <- create_edge_case_season(4, "normal")
  elo_data <- c("1" = 1500, "2" = 1500, "3" = 1500, "4" = 1500)
  
  # This should either error or return empty results
  expect_error(
    simulationsCPP(
      season = season_data,
      ELOValue = elo_data,
      numberTeams = 4,
      numberGames = nrow(season_data),
      iterations = 0
    ),
    "iteration|invalid",
    ignore.case = TRUE
  )
})

test_that("Tie-breaking scenarios are handled consistently", {
  # Create a scenario where teams are likely to tie on points
  tied_season <- data.frame(
    HomeTeam = c(1, 2, 3, 4, 1, 2),
    AwayTeam = c(2, 1, 4, 3, 3, 4),
    HomeGoals = c(1, 1, 1, 1, 1, 1),  # All draws
    AwayGoals = c(1, 1, 1, 1, 1, 1)
  )
  
  # Add some unplayed games
  tied_season <- rbind(
    tied_season,
    data.frame(
      HomeTeam = c(3, 4, 1, 2),
      AwayTeam = c(1, 2, 4, 3),
      HomeGoals = c(NA, NA, NA, NA),
      AwayGoals = c(NA, NA, NA, NA)
    )
  )
  
  tied_season_matrix <- as.matrix(tied_season)
  elo_data <- c("1" = 1500, "2" = 1500, "3" = 1500, "4" = 1500)
  
  result <- simulationsCPP(
    season = tied_season_matrix,
    ELOValue = elo_data,
    numberTeams = 4,
    numberGames = nrow(tied_season_matrix),
    iterations = 100
  )
  
  # Check that tie-breaking produces varied results
  expect_true(length(unique(result[,1])) > 1,
              info = "Tie-breaking should produce varied positions")
})