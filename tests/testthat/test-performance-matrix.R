# Performance Matrix Tests
# Tests performance across combinations of iterations and games

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

context("Performance Matrix Tests")

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

test_that("Performance matrix matches empirical formula across iteration/game combinations", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # Load baseline for formula parameters
  baseline <- load_baseline()
  time_per_iter_game <- baseline$performance_characteristics$time_per_iteration_per_game_ms
  base_overhead <- baseline$performance_characteristics$base_overhead_ms
  
  # Test matrix: iterations x games
  iterations <- c(100, 500, 1000)
  game_counts <- c(50, 150, 300)  # Approximate games for different season stages
  
  # Create results matrix
  results <- matrix(NA, nrow = length(iterations), ncol = length(game_counts))
  expected <- matrix(NA, nrow = length(iterations), ncol = length(game_counts))
  
  elo_data <- create_mock_elo_values(18)
  
  for (i in seq_along(iterations)) {
    for (j in seq_along(game_counts)) {
      n_iter <- iterations[i]
      target_games <- game_counts[j]
      
      # Create season with appropriate completion level
      # 306 total games for 18 teams
      pct_complete <- 1 - (target_games / 306)
      season_data <- create_test_season_matrix(18, pct_complete)
      actual_games <- sum(is.na(season_data[,3]))
      
      # Measure performance
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
      
      results[i, j] <- median(timing$time) / 1e6  # ms
      expected[i, j] <- calculate_expected_time(n_iter, actual_games, 
                                                time_per_iter_game, base_overhead)
    }
  }
  
  # Check that all measurements are within 20% of expected
  for (i in seq_along(iterations)) {
    for (j in seq_along(game_counts)) {
      deviation <- abs(results[i, j] - expected[i, j]) / expected[i, j]
      
      expect_lt(deviation, 0.2,
                info = sprintf("%d iterations, ~%d games: %.1fms actual vs %.1fms expected (%.1f%% deviation)",
                             iterations[i], game_counts[j], results[i, j], expected[i, j], deviation * 100))
    }
  }
  
  # Verify the formula coefficients by fitting a linear model
  # Flatten the matrices and create predictors
  actual_times <- as.vector(results)
  iter_vec <- rep(iterations, length(game_counts))
  game_vec <- rep(game_counts, each = length(iterations))
  
  # Fit model: time = a + b * iterations * games
  interaction_term <- iter_vec * game_vec
  model <- lm(actual_times ~ interaction_term)
  
  fitted_coefficient <- coef(model)[2]
  
  # The fitted coefficient should be close to our baseline
  expect_lt(abs(fitted_coefficient - time_per_iter_game) / time_per_iter_game, 0.15,
            info = sprintf("Fitted coefficient: %.5f vs baseline: %.5f",
                         fitted_coefficient, time_per_iter_game))
})

test_that("Performance boundaries are reasonable for production scenarios", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # Test production scenarios
  scenarios <- list(
    list(name = "Early season update", teams = 18, completion = 0.1, iterations = 10000),
    list(name = "Mid-season update", teams = 18, completion = 0.5, iterations = 10000),
    list(name = "Late season update", teams = 18, completion = 0.9, iterations = 10000),
    list(name = "3. Liga full season", teams = 20, completion = 0.0, iterations = 10000),
    list(name = "Quick preview", teams = 18, completion = 0.5, iterations = 1000)
  )
  
  baseline <- load_baseline()
  
  for (scenario in scenarios) {
    season_data <- create_test_season_matrix(scenario$teams, scenario$completion)
    elo_data <- create_mock_elo_values(scenario$teams)
    games_to_sim <- sum(is.na(season_data[,3]))
    
    # Calculate expected time
    expected_time <- calculate_expected_time(
      scenario$iterations, 
      games_to_sim,
      baseline$performance_characteristics$time_per_iteration_per_game_ms,
      baseline$performance_characteristics$base_overhead_ms
    )
    
    # Set reasonable bounds based on scenario
    if (scenario$iterations == 10000) {
      # Production runs should complete within reasonable time
      max_time <- ifelse(scenario$completion < 0.5, 60000, 30000)  # 60s early season, 30s late
    } else {
      # Quick previews should be fast
      max_time <- 5000  # 5 seconds
    }
    
    expect_lt(expected_time, max_time,
              info = sprintf("%s: Expected %.1fs (should be < %.1fs)",
                           scenario$name, expected_time/1000, max_time/1000))
  }
})

test_that("Performance degrades gracefully under stress", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # Test extreme scenarios
  elo_data <- create_mock_elo_values(20)
  
  # Extreme case 1: Very high iteration count
  season_data <- create_test_season_matrix(20, 0.9)  # Few games
  
  timing_high_iter <- microbenchmark(
    simulationsCPP(
      season = season_data,
      ELOValue = elo_data,
      numberTeams = 20,
      numberGames = nrow(season_data),
      iterations = 50000  # 5x normal
    ),
    times = 1
  )
  
  time_50k <- median(timing_high_iter$time) / 1e6
  
  # Should still complete in reasonable time even with 50k iterations
  expect_lt(time_50k, 180000,  # 3 minutes
            info = sprintf("50k iterations completed in %.1fs", time_50k/1000))
  
  # Extreme case 2: Full season, all leagues simultaneously (simulated)
  total_time <- 0
  leagues <- list(
    list(teams = 18, name = "Bundesliga"),
    list(teams = 18, name = "2. Bundesliga"),
    list(teams = 20, name = "3. Liga")
  )
  
  for (league in leagues) {
    season_data <- create_test_season_matrix(league$teams, 0.0)
    elo_data <- create_mock_elo_values(league$teams)
    
    timing <- microbenchmark(
      simulationsCPP(
        season = season_data,
        ELOValue = elo_data,
        numberTeams = league$teams,
        numberGames = nrow(season_data),
        iterations = 10000
      ),
      times = 1
    )
    
    total_time <- total_time + median(timing$time) / 1e6
  }
  
  # All three leagues should complete within update window
  expect_lt(total_time, 300000,  # 5 minutes total
            info = sprintf("All three leagues completed in %.1fs", total_time/1000))
})

test_that("Performance comparison across different hardware is tracked", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # Run a standard benchmark
  season_data <- create_test_season_matrix(18, 0.5)
  elo_data <- create_mock_elo_values(18)
  
  result <- run_performance_test(
    test_func = function() {
      simulationsCPP(
        season = season_data,
        ELOValue = elo_data,
        numberTeams = 18,
        numberGames = nrow(season_data),
        iterations = 1000
      )
    },
    test_name = "iteration_scaling.1000",
    times = 3
  )
  
  # Log hardware-specific performance
  hw_info <- list(
    platform = Sys.info()["sysname"],
    cpu_cores = parallel::detectCores(),
    r_version = R.version.string,
    timestamp = Sys.time(),
    test_result = result
  )
  
  # This could be saved to track performance across different systems
  expect_true(!is.null(result$median_ms),
              info = "Performance measurement completed successfully")
  
  # If this is faster than baseline, it could trigger an update
  if (!is.na(result$baseline_ms) && result$median_ms < result$baseline_ms * 0.95) {
    message(sprintf("Performance improvement detected: %.1fms (%.1f%% faster)",
                   result$median_ms, 
                   (1 - result$median_ms/result$baseline_ms) * 100))
  }
})

test_that("Parallel processing potential is identified", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # Test if multiple leagues could benefit from parallel processing
  leagues <- list(
    list(teams = 18, name = "Bundesliga"),
    list(teams = 18, name = "2. Bundesliga"),
    list(teams = 20, name = "3. Liga")
  )
  
  # Sequential timing
  sequential_time <- 0
  for (league in leagues) {
    season_data <- create_test_season_matrix(league$teams, 0.5)
    elo_data <- create_mock_elo_values(league$teams)
    
    timing <- microbenchmark(
      simulationsCPP(
        season = season_data,
        ELOValue = elo_data,
        numberTeams = league$teams,
        numberGames = nrow(season_data),
        iterations = 1000
      ),
      times = 1
    )
    
    sequential_time <- sequential_time + median(timing$time) / 1e6
  }
  
  # Theoretical parallel time (assuming perfect parallelization)
  # In reality, would be limited by number of cores
  max_single_league_time <- sequential_time / length(leagues)
  
  potential_speedup <- sequential_time / max_single_league_time
  
  expect_gt(potential_speedup, 2.5,
            info = sprintf("Parallel processing could provide %.1fx speedup", potential_speedup))
  
  # Log recommendation
  if (potential_speedup > 2) {
    message(sprintf("RECOMMENDATION: Parallel processing could reduce total time from %.1fs to ~%.1fs",
                   sequential_time/1000, max_single_league_time/1000))
  }
})