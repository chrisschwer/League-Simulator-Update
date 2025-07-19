# Performance Regression Tests
# Detects performance regressions by comparing against empirical baselines

library(testthat)
library(microbenchmark)

# Source helpers - handled by helper-test-setup.R
source("helper-performance-baseline.R")

context("Performance Regression Detection")

# Helper to create test data
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

create_test_elo <- function(n_teams) {
  set.seed(42)
  elo_values <- rnorm(n_teams, 1500, 150)
  elo_values <- pmax(1000, pmin(2000, elo_values))
  names(elo_values) <- 1:n_teams
  elo_values
}

test_that("Performance stays within baseline tolerance for key scenarios", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  baseline <- load_baseline()
  
  # Test 1: Standard 1000 iteration simulation
  season_data <- create_test_season_matrix(18, 0.5)
  elo_data <- create_test_elo(18)
  
  result_1000 <- run_performance_test(
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
  
  # Should be within 10% of baseline
  expect_true(result_1000$comparison$within_tolerance,
              info = sprintf("1000 iterations: %.1fms (baseline: %.1fms, %.1f%% change)",
                           result_1000$median_ms,
                           result_1000$baseline_ms,
                           result_1000$comparison$percent_change))
  
  # Test 2: Production simulation (10000 iterations)
  if (Sys.getenv("RUN_FULL_PERFORMANCE_TESTS") == "true") {
    result_10000 <- run_performance_test(
      test_func = function() {
        simulationsCPP(
          season = season_data,
          ELOValue = elo_data,
          numberTeams = 18,
          numberGames = nrow(season_data),
          iterations = 10000
        )
      },
      test_name = "iteration_scaling.10000",
      times = 1
    )
    
    expect_true(result_10000$comparison$within_tolerance,
                info = sprintf("10000 iterations: %.1fs (baseline: %.1fs)",
                             result_10000$median_ms / 1000,
                             result_10000$baseline_ms / 1000))
  }
})

test_that("Component performance remains stable", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  baseline <- load_baseline()
  
  # Test ELO calculation
  elo_result <- run_performance_test(
    test_func = function() {
      SpielNichtSimulieren(1500, 1400, 2, 1, 1.0, 65)
    },
    test_name = "component_performance.elo_calculation_ns",
    times = 10000
  )
  
  # Convert ns baseline to ms for comparison
  baseline_ms <- baseline$component_performance$elo_calculation_ns / 1e6
  current_ms <- elo_result$median_ms
  
  # Allow 20% tolerance for very fast operations
  ratio <- current_ms / baseline_ms
  expect_lt(ratio, 1.2,
            info = sprintf("ELO calculation: %.3fms vs baseline %.3fms (%.1fx)",
                         current_ms, baseline_ms, ratio))
})

test_that("Performance improvements are detected and logged", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # This test verifies the improvement detection mechanism
  # It doesn't fail if no improvement is found
  
  season_data <- create_test_season_matrix(18, 0.5)
  elo_data <- create_test_elo(18)
  
  result <- run_performance_test(
    test_func = function() {
      simulationsCPP(
        season = season_data,
        ELOValue = elo_data,
        numberTeams = 18,
        numberGames = nrow(season_data),
        iterations = 100
      )
    },
    test_name = "iteration_scaling.100",
    times = 5
  )
  
  # Check if improvement was detected
  if (!is.na(result$baseline_ms) && result$comparison$ratio < 0.95) {
    # Log the improvement
    message(sprintf("Performance improvement detected: %.1f%% faster than baseline",
                   (1 - result$comparison$ratio) * 100))
    
    # In a real scenario, this could trigger baseline update
    # update_baseline_if_faster(...)
  }
  
  # Test always passes - it's just for monitoring
  expect_true(TRUE)
})

test_that("Performance regression report is generated", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  # Run a set of performance tests
  test_results <- list()
  
  # Small iteration test
  season_data <- create_test_season_matrix(18, 0.5)
  elo_data <- create_test_elo(18)
  
  timing_100 <- microbenchmark(
    simulationsCPP(season_data, elo_data, 18, nrow(season_data), 100),
    times = 5
  )
  test_results[["100"]] <- median(timing_100$time) / 1e6
  
  # Generate report
  report <- generate_performance_report(test_results)
  
  # Verify report structure
  expect_true(!is.null(report$timestamp))
  expect_true(!is.null(report$system))
  expect_true(!is.null(report$test_results))
  expect_true(!is.null(report$baseline_comparison))
  
  # Check if any regressions were detected
  if (length(report$baseline_comparison) > 0) {
    regressions <- sapply(report$baseline_comparison, function(x) {
      !is.null(x$within_tolerance) && !x$within_tolerance
    })
    
    if (any(regressions)) {
      warning(sprintf("%d performance regression(s) detected", sum(regressions)))
    }
  }
})

test_that("Memory usage remains stable across repeated simulations", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  season_data <- create_test_season_matrix(18, 0.5)
  elo_data <- create_test_elo(18)
  
  # Force garbage collection and measure initial memory
  gc()
  initial_mem <- sum(gc()[, 2])  # Total memory used
  
  # Run multiple simulations
  for (i in 1:5) {
    result <- simulationsCPP(
      season = season_data,
      ELOValue = elo_data,
      numberTeams = 18,
      numberGames = nrow(season_data),
      iterations = 100
    )
    rm(result)
  }
  
  # Force garbage collection and measure final memory
  gc()
  final_mem <- sum(gc()[, 2])
  
  # Memory growth should be minimal (< 5MB)
  mem_growth_mb <- final_mem - initial_mem
  expect_lt(mem_growth_mb, 5,
            info = sprintf("Memory grew by %.1f MB after 5 simulations", mem_growth_mb))
})

test_that("Performance scales predictably with input size", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true",
              "Set RUN_PERFORMANCE_TESTS=true to run performance tests")
  
  baseline <- load_baseline()
  formula_coef <- baseline$performance_characteristics$time_per_iteration_per_game_ms
  formula_base <- baseline$performance_characteristics$base_overhead_ms
  
  # Test various combinations
  test_cases <- list(
    list(teams = 18, completion = 0.5, iterations = 500),
    list(teams = 18, completion = 0.2, iterations = 1000),
    list(teams = 20, completion = 0.5, iterations = 500)
  )
  
  for (tc in test_cases) {
    season_data <- create_test_season_matrix(tc$teams, tc$completion)
    elo_data <- create_test_elo(tc$teams)
    games_to_sim <- sum(is.na(season_data[,3]))
    
    timing <- microbenchmark(
      simulationsCPP(season_data, elo_data, tc$teams, nrow(season_data), tc$iterations),
      times = 3
    )
    
    actual_time <- median(timing$time) / 1e6
    expected_time <- calculate_expected_time(tc$iterations, games_to_sim, 
                                           formula_coef, formula_base)
    
    deviation <- abs(actual_time - expected_time) / expected_time
    
    expect_lt(deviation, 0.25,  # Allow 25% deviation
              info = sprintf("%d teams, %.0f%% complete, %d iter: %.1fms actual vs %.1fms expected",
                           tc$teams, tc$completion * 100, tc$iterations, 
                           actual_time, expected_time))
  }
})