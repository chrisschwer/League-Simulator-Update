# Integration Tests for Rust Simulation Engine
# Validates that Rust produces equivalent results to R/C++ implementation

library(testthat)

# Source required functions
source("RCode/rust_integration.R")
Rcpp::sourceCpp("RCode/SpielNichtSimulieren.cpp")
source("RCode/leagueSimulatorCPP.R")
source("RCode/SaisonSimulierenCPP.R")
source("RCode/simulationsCPP.R")
source("RCode/SpielCPP.R")
source("RCode/Tabelle.R")
source("RCode/transform_data.R")
source("RCode/prozent.R")

# Test configuration
RUST_API_URL <- Sys.getenv("RUST_API_URL", "http://localhost:8080")
TEST_ITERATIONS <- 1000  # Use fewer iterations for testing

test_that("Rust simulator is accessible", {
  skip_if_not(connect_rust_simulator(), "Rust simulator not available")
  
  response <- httr::GET(paste0(RUST_API_URL, "/health"))
  expect_equal(httr::status_code(response), 200)
  
  health <- httr::content(response, "parsed")
  expect_true("version" %in% names(health))
  expect_true("performance" %in% names(health))
})

test_that("Rust produces valid probability matrices", {
  skip_if_not(connect_rust_simulator(), "Rust simulator not available")
  
  # Create test data
  season_data <- data.frame(
    TeamHeim = c("Team1", "Team2", "Team3", "Team1", "Team2", "Team3"),
    TeamGast = c("Team2", "Team3", "Team1", "Team3", "Team1", "Team2"),
    ToreHeim = c(2, 1, NA, NA, NA, NA),
    ToreGast = c(1, 1, NA, NA, NA, NA),
    Team1 = rep(1500, 6),
    Team2 = rep(1600, 6),
    Team3 = rep(1400, 6)
  )
  
  # Run Rust simulation
  result <- leagueSimulatorRust(season_data, n = TEST_ITERATIONS, numberTeams = 3)
  
  # Validate result structure
  expect_true(is.matrix(result))
  expect_equal(nrow(result), 3)  # 3 teams
  expect_equal(ncol(result), 3)  # 3 positions
  
  # Validate probabilities
  for (i in 1:nrow(result)) {
    row_sum <- sum(result[i, ])
    expect_equal(row_sum, 1.0, tolerance = 0.01)  # Each team's probabilities sum to 1
    
    for (j in 1:ncol(result)) {
      expect_gte(result[i, j], 0)  # No negative probabilities
      expect_lte(result[i, j], 1)  # No probabilities > 1
    }
  }
  
  # Check team names preserved
  expect_true(all(c("Team1", "Team2", "Team3") %in% rownames(result)))
})

test_that("Rust and C++ produce similar results", {
  skip_if_not(connect_rust_simulator(), "Rust simulator not available")
  
  # Create test season
  season_data <- data.frame(
    TeamHeim = c("Bayern", "Dortmund", "Leipzig", "Bayern", "Dortmund", "Leipzig"),
    TeamGast = c("Dortmund", "Leipzig", "Bayern", "Leipzig", "Bayern", "Dortmund"),
    ToreHeim = c(2, 1, 0, NA, NA, NA),
    ToreGast = c(1, 0, 1, NA, NA, NA),
    Bayern = rep(1800, 6),
    Dortmund = rep(1700, 6),
    Leipzig = rep(1650, 6)
  )
  
  # Run both simulations with same seed for reproducibility
  set.seed(42)
  result_cpp <- leagueSimulatorCPP(season_data, n = TEST_ITERATIONS, numberTeams = 3)
  
  set.seed(42)
  result_rust <- leagueSimulatorRust(season_data, n = TEST_ITERATIONS, numberTeams = 3)
  
  # Compare dimensions
  expect_equal(dim(result_rust), dim(result_cpp))
  
  # Compare probability distributions (should be similar but not exact due to RNG differences)
  for (i in 1:nrow(result_rust)) {
    for (j in 1:ncol(result_rust)) {
      # Allow 10% tolerance due to Monte Carlo randomness
      expect_equal(result_rust[i, j], result_cpp[i, j], 
                   tolerance = 0.1,
                   label = sprintf("Position [%d, %d]", i, j))
    }
  }
  
  # Check that strongest team (Bayern) has highest probability of 1st place
  bayern_idx <- which(rownames(result_rust) == "Bayern")
  expect_gt(result_rust[bayern_idx, 1], result_rust[bayern_idx, 2])
  expect_gt(result_rust[bayern_idx, 1], result_rust[bayern_idx, 3])
})

test_that("Rust handles edge cases correctly", {
  skip_if_not(connect_rust_simulator(), "Rust simulator not available")
  
  # Test 1: Season with all games played
  season_complete <- data.frame(
    TeamHeim = c("A", "B"),
    TeamGast = c("B", "A"),
    ToreHeim = c(3, 1),
    ToreGast = c(0, 2),
    A = rep(1500, 2),
    B = rep(1500, 2)
  )
  
  result <- leagueSimulatorRust(season_complete, n = 100, numberTeams = 2)
  
  # With all games played, probabilities should be deterministic
  expect_equal(result[1, 1], 1.0)  # Team A definitely 1st
  expect_equal(result[2, 2], 1.0)  # Team B definitely 2nd
  
  # Test 2: Season with no games played
  season_empty <- data.frame(
    TeamHeim = c("A", "B"),
    TeamGast = c("B", "A"),
    ToreHeim = c(NA, NA),
    ToreGast = c(NA, NA),
    A = rep(1500, 2),
    B = rep(1500, 2)
  )
  
  result <- leagueSimulatorRust(season_empty, n = TEST_ITERATIONS, numberTeams = 2)
  
  # With equal ELOs and no games played, probabilities should be ~50/50
  expect_equal(result[1, 1], 0.5, tolerance = 0.1)
  expect_equal(result[1, 2], 0.5, tolerance = 0.1)
})

test_that("Rust handles point adjustments correctly", {
  skip_if_not(connect_rust_simulator(), "Rust simulator not available")
  
  season_data <- data.frame(
    TeamHeim = c("A", "B", "C"),
    TeamGast = c("B", "C", "A"),
    ToreHeim = c(1, 1, 1),
    ToreGast = c(1, 1, 1),
    A = rep(1500, 3),
    B = rep(1500, 3),
    C = rep(1500, 3)
  )
  
  # Without adjustments - all teams equal
  result_normal <- leagueSimulatorRust(season_data, n = TEST_ITERATIONS, 
                                       numberTeams = 3)
  
  # With point penalty for team B
  result_penalty <- leagueSimulatorRust(season_data, n = TEST_ITERATIONS,
                                        numberTeams = 3,
                                        adjPoints = c(0, -6, 0))  # -6 points for team B
  
  # Team B should have much lower probability of 1st place with penalty
  b_idx <- which(rownames(result_penalty) == "B")
  expect_lt(result_penalty[b_idx, 1], result_normal[b_idx, 1])
  expect_gt(result_penalty[b_idx, 3], result_normal[b_idx, 3])  # Higher probability of last
})

test_that("Rust performance is significantly better than C++", {
  skip_if_not(connect_rust_simulator(), "Rust simulator not available")
  
  # Create larger test case
  teams <- 18
  games <- 306  # Full Bundesliga season
  
  team_names <- paste0("Team", 1:teams)
  
  # Generate full season schedule
  schedule <- expand.grid(
    TeamHeim = team_names,
    TeamGast = team_names,
    stringsAsFactors = FALSE
  )
  schedule <- schedule[schedule$TeamHeim != schedule$TeamGast, ]
  
  # Add match results (half played, half unplayed)
  n_games <- nrow(schedule)
  schedule$ToreHeim <- c(sample(0:4, n_games/2, replace = TRUE), 
                         rep(NA, n_games - n_games/2))
  schedule$ToreGast <- c(sample(0:4, n_games/2, replace = TRUE),
                         rep(NA, n_games - n_games/2))
  
  # Add ELO columns
  for (team in team_names) {
    schedule[[team]] <- rep(1500 + rnorm(1, 0, 100), nrow(schedule))
  }
  
  # Measure C++ performance
  start_cpp <- Sys.time()
  result_cpp <- leagueSimulatorCPP(schedule, n = 1000, numberTeams = teams)
  time_cpp <- as.numeric(difftime(Sys.time(), start_cpp, units = "secs"))
  
  # Measure Rust performance
  start_rust <- Sys.time()
  result_rust <- leagueSimulatorRust(schedule, n = 1000, numberTeams = teams)
  time_rust <- as.numeric(difftime(Sys.time(), start_rust, units = "secs"))
  
  speedup <- time_cpp / time_rust
  
  message(sprintf("C++ time: %.2f seconds", time_cpp))
  message(sprintf("Rust time: %.2f seconds", time_rust))
  message(sprintf("Speedup: %.1fx", speedup))
  
  # Rust should be at least 10x faster (conservative estimate)
  expect_gt(speedup, 10)
})

# Run tests if called directly
if (sys.nframe() == 0) {
  test_results <- test_file("tests/test_rust_integration.R")
  print(test_results)
}