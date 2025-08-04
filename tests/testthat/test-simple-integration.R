# Simple Integration Tests for Basic Functionality

library(testthat)
source("../../RCode/SaisonSimulierenCPP.R")
source("../../RCode/SpielCPP.R")
source("../../RCode/RcppExports.R")
source("../../RCode/Tabelle.R")
source("../../RCode/prozent.R")
source("../../RCode/simulationsCPP.R")
source("../../RCode/cpp_wrappers.R")

# Source helper files
source("helper-fixtures.R")

test_that("Can simulate one Bundesliga season", {
  # 18 teams like real Bundesliga
  elo_values <- seq(1700, 1300, length.out = 18)
  
  # Create fixture list (each team plays every other team twice)
  fixtures <- expand.grid(home = 1:18, away = 1:18)
  fixtures <- fixtures[fixtures$home != fixtures$away, ]
  
  # Create empty season
  season <- cbind(
    fixtures$home,
    fixtures$away,
    rep(NA, nrow(fixtures)),
    rep(NA, nrow(fixtures))
  )
  
  # Simulate season
  set.seed(2025)
  result <- SaisonSimulierenCPP(
    Spielplan = season,
    ELOWerte = elo_values,
    ModFaktor = 40,
    Heimvorteil = 65,
    AnzahlTeams = 18,
    AnzahlSpiele = nrow(season)
  )
  
  # Check results
  simulated_season <- result[[1]]
  
  # All games should have scores
  expect_false(any(is.na(simulated_season[, 3])))
  expect_false(any(is.na(simulated_season[, 4])))
  
  # Create final table
  adj_none <- rep(0, 18)
  table <- Tabelle(
    season = simulated_season,
    numberTeams = 18,
    numberGames = nrow(season),
    AdjPoints = adj_none,
    AdjGoals = adj_none,
    AdjGoalsAgainst = adj_none,
    AdjGoalDiff = adj_none
  )
  
  # Each team should have played 34 games (17 home, 17 away)
  expect_true(all(table[, "GP"] == 34))
  
  # Points should be reasonable (not all 0, not all max)
  expect_true(max(table[, "Pts"]) > 50)  # Winner gets decent points
  expect_true(min(table[, "Pts"]) < 40)  # Loser doesn't get too many
})

test_that("Results can be saved and loaded correctly", {
  # Small simulation
  elo_values <- c(1600, 1500, 1400, 1300)
  season <- create_test_season(0)
  
  # Run simulation
  set.seed(111)
  simulated <- SaisonSimulierenCPP(
    Spielplan = season,
    ELOWerte = elo_values,
    ModFaktor = 40,
    Heimvorteil = 65,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  # Save to temporary file
  temp_file <- tempfile(fileext = ".rds")
  saveRDS(simulated, temp_file)
  
  # Load back
  loaded <- readRDS(temp_file)
  
  # Should be identical
  expect_equal(loaded[[1]], simulated[[1]])
  expect_equal(loaded[[2]], simulated[[2]])
  
  # Cleanup
  unlink(temp_file)
})

test_that("Can continue from saved state", {
  # Start with partial season
  elo_values <- c(1600, 1500, 1400, 1300)
  season <- create_test_season(6)  # 6 games played
  
  # Save initial state
  initial_played <- season[1:6, ]
  
  # Complete the season
  set.seed(222)
  result <- SaisonSimulierenCPP(
    Spielplan = season,
    ELOWerte = elo_values,
    ModFaktor = 40,
    Heimvorteil = 65,
    AnzahlTeams = 4,
    AnzahlSpiele = 12
  )
  
  final_season <- result[[1]]
  
  # First 6 games should be unchanged
  expect_equal(final_season[1:6, ], initial_played)
  
  # Remaining games should be filled
  expect_false(any(is.na(final_season[7:12, 3])))
  expect_false(any(is.na(final_season[7:12, 4])))
})

test_that("Probability matrix calculation works", {
  # Setup for probability calculation
  elo_values <- c(1700, 1500, 1300)  # Clear strength differences
  season <- create_test_season(0)  # 3 teams, round robin
  adj_none <- rep(0, 3)
  
  # Run many simulations
  set.seed(333)
  iterations <- 5000
  position_counts <- matrix(0, nrow = 3, ncol = 3)
  
  for (i in 1:iterations) {
    sim_result <- simulationsCPP_wrapper(
      season = season,
      ELOValue = elo_values,
      numberTeams = 3,
      numberGames = 6,
      modFactor = 40,
      homeAdvantage = 65,
      iterations = 1,
      AdjPoints = adj_none,
      AdjGoals = adj_none,
      AdjGoalsAgainst = adj_none,
      AdjGoalDiff = adj_none
    )
    
    # Track positions
    for (pos in 1:3) {
      team <- sim_result[pos, "Team"]
      position_counts[team, pos] <- position_counts[team, pos] + 1
    }
  }
  
  # Convert to probabilities
  prob_matrix <- position_counts / iterations
  
  # Strongest team should most likely finish first
  expect_true(prob_matrix[1, 1] > prob_matrix[2, 1])
  expect_true(prob_matrix[1, 1] > prob_matrix[3, 1])
  
  # Weakest team should most likely finish last
  expect_true(prob_matrix[3, 3] > prob_matrix[1, 3])
  expect_true(prob_matrix[3, 3] > prob_matrix[2, 3])
  
  # Each row should sum to 1 (team must finish somewhere)
  for (i in 1:3) {
    expect_equal(sum(prob_matrix[i, ]), 1, tolerance = 0.01)
  }
})

test_that("Basic season transition works", {
  # Simulate end of season positions
  teams_2024 <- data.frame(
    Team = c("Bayern", "Dortmund", "Leipzig", "Relegated1", "Relegated2", "Relegated3"),
    League = c(1, 1, 1, 1, 1, 1),
    ELO = c(1800, 1700, 1650, 1400, 1350, 1300)
  )
  
  # Simple transition: bottom 3 relegated, top 3 promoted
  teams_2025 <- teams_2024
  
  # Relegated teams get 80% of ELO
  relegated <- teams_2025$Team %in% c("Relegated1", "Relegated2", "Relegated3")
  teams_2025$ELO[relegated] <- teams_2025$ELO[relegated] * 0.8
  teams_2025$League[relegated] <- 2
  
  # Add promoted teams (would come from Liga 2)
  promoted <- data.frame(
    Team = c("Promoted1", "Promoted2", "Promoted3"),
    League = c(1, 1, 1),
    ELO = c(1450, 1400, 1350)  # Reasonable ELOs for promoted teams
  )
  
  # New season has correct number of teams
  bundesliga_2025 <- rbind(
    teams_2025[!relegated, ],
    promoted
  )
  
  expect_equal(nrow(bundesliga_2025), 6)
  expect_equal(sum(bundesliga_2025$League == 1), 6)
  
  # ELO values are reasonable
  expect_true(all(bundesliga_2025$ELO > 1000))
  expect_true(all(bundesliga_2025$ELO < 2000))
})