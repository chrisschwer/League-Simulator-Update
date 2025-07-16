# Performance Scaling Validation Tests
# Tests to verify O(N) scaling based on empirical measurements

library(testthat)
library(microbenchmark)

# Source helpers
source("tests/testthat/helper-performance-baseline.R")
source("tests/testthat/test-helpers/elo-mock-generator.R")

# Source simulation functions
source("RCode/simulationsCPP.R")
source("RCode/SaisonSimulierenCPP.R")
source("RCode/SpielCPP.R")
library(Rcpp)
sourceCpp("RCode/SpielNichtSimulieren.cpp")

context("Performance Scaling Validation")

# Helper to create test season
create_test_season_matrix <- function(n_teams, pct_complete) {
  total_games <- n_teams * (n_teams - 1)
  games_played <- floor(total_games * pct_complete)
  
  fixtures <- expand.grid(HomeTeam = 1:n_teams, AwayTeam = 1:n_teams)
  fixtures <- fixtures[fixtures$HomeTeam != fixtures$AwayTeam, ]
  
  fixtures$HomeGoals <- NA
  fixtures$AwayGoals <- NA
  
  if (games_played > 0) {
    set.seed(42)
    fixtures$HomeGoals[1:games_played] <- rpois(games_played, 1.5)
    fixtures$AwayGoals[1:games_played] <- rpois(games_played, 1.2)
  }
  
  as.matrix(fixtures)
}

test_that("Simulation scales O(N) with iteration count", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # Test data
  season_data <- create_test_season_matrix(18, 0.5)
  elo_data <- create_mock_elo_values(18)
  
  # Test different iteration counts
  iteration_counts <- c(100, 200, 500, 1000)
  times <- numeric(length(iteration_counts))
  
  for (i in seq_along(iteration_counts)) {
    n_iter <- iteration_counts[i]
    
    timing <- microbenchmark(
      simulationsCPP(
        season = season_data,
        ELOValue = elo_data,
        numberTeams = 18,
        numberGames = nrow(season_data),
        iterations = n_iter
      ),
      times = 3
    )
    
    times[i] <- median(timing$time) / 1e6  # ms
  }
  
  # Verify linear scaling
  scaling_result <- verify_linear_scaling(times, iteration_counts)
  
  expect_true(scaling_result$is_linear,
              info = sprintf("Scaling factors: %s (mean: %.2f, should be ~1.0)",
                           paste(round(scaling_result$scaling_factors, 2), collapse=", "),
                           scaling_result$mean_factor))
  
  # Check individual scaling factors
  for (i in seq_along(scaling_result$scaling_factors)) {
    expect_lt(abs(scaling_result$scaling_factors[i] - 1.0), 0.2,
              info = sprintf("Scaling factor %d->%d iterations: %.2f (expected ~1.0)",
                           iteration_counts[i], iteration_counts[i+1],
                           scaling_result$scaling_factors[i]))
  }
  
  # Compare with baseline formula
  baseline <- load_baseline()
  for (i in seq_along(iteration_counts)) {
    expected_time <- calculate_expected_time(
      iteration_counts[i], 
      sum(is.na(season_data[,3])),
      baseline$performance_characteristics$time_per_iteration_per_game_ms
    )
    
    # Allow 20% deviation from formula
    expect_lt(abs(times[i] - expected_time) / expected_time, 0.2,
              info = sprintf("%d iterations: %.1fms actual vs %.1fms expected",
                           iteration_counts[i], times[i], expected_time))
  }
})

test_that("Simulation scales O(N) with game count", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  elo_data <- create_mock_elo_values(18)
  
  # Test different season completion levels
  completion_levels <- c(0.9, 0.7, 0.5, 0.3, 0.1)
  games_to_simulate <- numeric(length(completion_levels))
  times <- numeric(length(completion_levels))
  
  for (i in seq_along(completion_levels)) {
    season_data <- create_test_season_matrix(18, completion_levels[i])
    games_to_simulate[i] <- sum(is.na(season_data[,3]))
    
    timing <- microbenchmark(
      simulationsCPP(
        season = season_data,
        ELOValue = elo_data,
        numberTeams = 18,
        numberGames = nrow(season_data),
        iterations = 1000
      ),
      times = 3
    )
    
    times[i] <- median(timing$time) / 1e6  # ms
  }
  
  # Verify linear scaling with games
  scaling_result <- verify_linear_scaling(times, games_to_simulate)
  
  expect_true(scaling_result$is_linear,
              info = sprintf("Game scaling factors: %s (mean: %.2f)",
                           paste(round(scaling_result$scaling_factors, 2), collapse=", "),
                           scaling_result$mean_factor))
  
  # Calculate time per game
  # Use linear regression to find slope
  lm_fit <- lm(times ~ games_to_simulate)
  time_per_game <- coef(lm_fit)[2]
  
  # Compare with baseline
  baseline <- load_baseline()
  expected_time_per_game <- baseline$performance_characteristics$time_per_iteration_per_game_ms * 1000
  
  expect_lt(abs(time_per_game - expected_time_per_game) / expected_time_per_game, 0.2,
            info = sprintf("Time per game: %.3fms actual vs %.3fms expected",
                         time_per_game, expected_time_per_game))
})

test_that("Component performance matches baseline", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  baseline <- load_baseline()
  
  # Test 1: ELO calculation performance
  elo_timing <- microbenchmark(
    SpielNichtSimulieren(1500, 1400, 2, 1, 1.0, 65),
    times = 10000
  )
  elo_time_ns <- median(elo_timing$time)
  
  expect_performance(
    elo_time_ns / 1e6,  # Convert to ms for comparison
    baseline$component_performance$elo_calculation_ns / 1e6,
    tolerance = 1.2,
    test_name = "ELO calculation"
  )
  
  # Test 2: Match simulation performance
  match_timing <- microbenchmark(
    SpielCPP(1500, 1400, runif(1), runif(1), 20, 65, TRUE),
    times = 1000
  )
  match_time_us <- median(match_timing$time) / 1000
  
  expect_performance(
    match_time_us / 1000,  # Convert to ms
    baseline$component_performance$match_simulation_us / 1000,
    tolerance = 1.2,
    test_name = "Match simulation"
  )
})

test_that("Performance degradation is detected", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  baseline <- load_baseline()
  
  # Simulate a slow operation
  slow_simulation <- function() {
    Sys.sleep(0.001)  # Add 1ms delay
    return(TRUE)
  }
  
  # This should fail the performance test
  expect_error(
    expect_performance(
      1001,  # 1001ms (simulated slow time)
      100,   # 100ms baseline
      tolerance = 1.1,
      test_name = "Simulated slow operation"
    ),
    regexp = "Performance regression detected"
  )
})

test_that("Scaling remains linear across different league sizes", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # Test scaling for different league sizes
  team_counts <- c(10, 14, 18, 20)
  times_per_game <- numeric(length(team_counts))
  
  for (i in seq_along(team_counts)) {
    n_teams <- team_counts[i]
    season_data <- create_test_season_matrix(n_teams, 0.5)
    elo_data <- create_mock_elo_values(n_teams)
    games_to_sim <- sum(is.na(season_data[,3]))
    
    timing <- microbenchmark(
      simulationsCPP(
        season = season_data,
        ELOValue = elo_data,
        numberTeams = n_teams,
        numberGames = nrow(season_data),
        iterations = 100
      ),
      times = 3
    )
    
    time_ms <- median(timing$time) / 1e6
    times_per_game[i] <- time_ms / (100 * games_to_sim)  # Time per iteration per game
  }
  
  # Check that time per game is consistent across league sizes
  cv <- sd(times_per_game) / mean(times_per_game)  # Coefficient of variation
  
  expect_lt(cv, 0.15,
            info = sprintf("Time per game varies by %.1f%% across league sizes (should be <15%%)",
                         cv * 100))
})

test_that("Memory usage scales linearly", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # This test ensures no memory leaks
  season_data <- create_test_season_matrix(18, 0.5)
  elo_data <- create_mock_elo_values(18)
  
  # Force garbage collection
  gc()
  initial_mem <- as.numeric(gc()[2, 2])  # Used memory in MB
  
  # Run multiple simulations
  for (i in 1:10) {
    result <- simulationsCPP(
      season = season_data,
      ELOValue = elo_data,
      numberTeams = 18,
      numberGames = nrow(season_data),
      iterations = 100
    )
    rm(result)
  }
  
  # Force garbage collection again
  gc()
  final_mem <- as.numeric(gc()[2, 2])
  
  mem_growth <- final_mem - initial_mem
  
  # Memory growth should be minimal (< 10MB)
  expect_lt(mem_growth, 10,
            info = sprintf("Memory grew by %.1f MB after 10 simulations", mem_growth))
})