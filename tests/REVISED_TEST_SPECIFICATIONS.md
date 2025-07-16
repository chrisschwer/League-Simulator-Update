# Revised Comprehensive Test Specifications

Following the human feedback on performance testing, these revised specifications incorporate empirically-based performance assertions, scaling validation, historical tracking, and comprehensive test coverage for all edge cases.

## 1. Performance Testing Specifications (REVISED)

### A. Empirically-Based Performance Tests

```r
# tests/testthat/test-performance-empirical.R
test_that("Monte Carlo simulation meets empirical performance baselines", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true")
  
  # Load empirical baseline
  baseline <- load_baseline()
  
  # Test with production parameters
  fixture_data <- create_test_season(18, 0.5)  # 50% season complete
  elo_data <- create_test_elo_values(18)
  
  # Run performance test with baseline comparison
  result <- run_performance_test(
    test_func = function() {
      simulationsCPP(fixture_data, elo_data, 18, nrow(fixture_data), 10000)
    },
    test_name = "iteration_scaling.10000",
    times = 1  # Single run for 10k iterations
  )
  
  # Assert performance is within 10% of historical best
  expect_performance(
    result$median_ms,
    result$baseline_ms,
    tolerance = 1.1,
    test_name = "10k iteration simulation"
  )
  
  # Update baseline if significantly faster
  if (result$median_ms < result$baseline_ms * 0.95) {
    update_baseline_if_faster("empirical_baseline.json", 
                              "iteration_scaling.10000", 
                              result$median_ms)
  }
})

test_that("Performance scales O(N) with iterations", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true")
  
  season_data <- create_test_season(18, 0.5)
  elo_data <- create_test_elo_values(18)
  
  # Test scaling across different iteration counts
  iteration_tests <- c(100, 1000, 10000)
  times <- numeric(length(iteration_tests))
  
  for (i in seq_along(iteration_tests)) {
    timing <- microbenchmark(
      simulationsCPP(season_data, elo_data, 18, nrow(season_data), iteration_tests[i]),
      times = ifelse(iteration_tests[i] > 1000, 1, 3)
    )
    times[i] <- median(timing$time) / 1e6
  }
  
  # Verify O(N) scaling
  scaling_result <- verify_linear_scaling(times, iteration_tests)
  
  expect_true(scaling_result$is_linear,
              info = sprintf("Scaling factors: %s (should be ~1.0 for O(N))",
                           paste(round(scaling_result$scaling_factors, 2), collapse=", ")))
  
  # Each 10x increase should take ~10x time (±20%)
  for (i in 2:length(times)) {
    if (iteration_tests[i] == iteration_tests[i-1] * 10) {
      ratio <- times[i] / times[i-1]
      expect_gt(ratio, 8)   # At least 8x
      expect_lt(ratio, 12)  # At most 12x
    }
  }
})
```

### B. Performance Matrix Tests (Iterations × Games)

```r
# tests/testthat/test-performance-matrix.R
test_that("Performance follows empirical formula: time = base + (iter × games × coefficient)", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true")
  
  baseline <- load_baseline()
  coef <- baseline$performance_characteristics$time_per_iteration_per_game_ms
  base <- baseline$performance_characteristics$base_overhead_ms
  
  # Test matrix
  test_cases <- expand.grid(
    iterations = c(100, 1000, 5000),
    games = c(50, 150, 300)
  )
  
  elo_data <- create_test_elo_values(18)
  
  for (i in 1:nrow(test_cases)) {
    iter <- test_cases$iterations[i]
    target_games <- test_cases$games[i]
    
    # Create season with appropriate number of unplayed games
    completion <- 1 - (target_games / 306)  # 306 total games for 18 teams
    season_data <- create_test_season(18, completion)
    actual_games <- sum(is.na(season_data$HomeGoals))
    
    # Measure actual time
    timing <- microbenchmark(
      simulationsCPP(season_data, elo_data, 18, nrow(season_data), iter),
      times = 3
    )
    actual_time <- median(timing$time) / 1e6
    
    # Calculate expected time
    expected_time <- calculate_expected_time(iter, actual_games, coef, base)
    
    # Allow 20% deviation from formula
    deviation <- abs(actual_time - expected_time) / expected_time
    expect_lt(deviation, 0.2,
              info = sprintf("%d iter × %d games: %.1fms actual vs %.1fms expected (%.1f%% dev)",
                           iter, actual_games, actual_time, expected_time, deviation * 100))
  }
})
```

### C. Historical Performance Tracking

```r
# tests/testthat/test-performance-tracking.R
test_that("Performance tracking system maintains history", {
  skip_if_not(Sys.getenv("RUN_PERFORMANCE_TESTS") == "true")
  
  # Run standard benchmark
  season_data <- create_test_season(18, 0.5)
  elo_data <- create_test_elo_values(18)
  
  result <- run_performance_test(
    test_func = function() {
      simulationsCPP(season_data, elo_data, 18, nrow(season_data), 1000)
    },
    test_name = "iteration_scaling.1000"
  )
  
  # Generate performance report
  report <- generate_performance_report(list("1000" = result$median_ms))
  
  # Verify report structure
  expect_true(file.exists(attr(report, "file_path")))
  expect_true(!is.null(report$baseline_comparison))
  expect_true(!is.null(report$system))
  
  # Check for performance trends
  if (length(report$baseline_comparison) > 0) {
    regressions <- sum(sapply(report$baseline_comparison, function(x) !x$within_tolerance))
    expect_equal(regressions, 0, 
                 info = "No performance regressions should be detected")
  }
})
```

## 2. Shiny Application Test Specifications

### A. UI Component Tests with Reactivity

```r
# tests/testthat/test-shiny-ui.R
test_that("Shiny UI components render and update correctly", {
  # Create mock data
  mock_results <- list(
    Bundesliga = create_mock_simulation_results(18),
    `2. Bundesliga` = create_mock_simulation_results(18),
    `Dritte Liga` = create_mock_simulation_results(20)
  )
  
  with_mock_file("data/Ergebnis.Rds", mock_results, {
    testServer(app, {
      # Initial state
      expect_equal(input$Liga, "Bundesliga")
      expect_true(inherits(output$Plot, "shiny.render.function"))
      
      # Test league switching
      session$setInputs(Liga = "2. Bundesliga")
      session$flushReact()
      
      # Verify plot updates
      plot_output <- output$Plot()
      expect_true(inherits(plot_output, "ggplot"))
      expect_equal(nrow(plot_output$data), 18)  # 18 teams in 2. Bundesliga
      
      # Test 3. Liga (20 teams)
      session$setInputs(Liga = "Dritte Liga")
      session$flushReact()
      
      plot_output <- output$Plot()
      expect_equal(nrow(plot_output$data), 20)  # 20 teams in 3. Liga
      
      # Test table outputs
      expect_true(!is.null(output$Oben))
      expect_true(!is.null(output$Unten))
    })
  })
})

test_that("Shiny app handles missing data gracefully", {
  testServer(app, {
    # Simulate missing file
    with_mock(
      `load` = function(...) stop("cannot open file"),
      {
        expect_error(session$flushReact(), "cannot open file")
        # App should show error message, not crash
        expect_true(session$isClosed() == FALSE)
      }
    )
  })
})
```

### B. Plot Generation Tests

```r
# tests/testthat/test-shiny-plots.R
test_that("Heatmap generation works for all league configurations", {
  # Test data for each league
  leagues <- list(
    list(name = "Bundesliga", teams = 18, groups = list(1:4, 5:6, 7, 16, 17:18)),
    list(name = "2. Bundesliga", teams = 18, groups = list(1:2, 3, 16, 17:18)),
    list(name = "Dritte Liga", teams = 20, groups = list(1:3, 4, 18:20))
  )
  
  for (league in leagues) {
    results <- create_mock_simulation_results(league$teams)
    
    plot <- display_result(results, league$name, league$groups)
    
    # Verify plot structure
    expect_true(inherits(plot, "ggplot"))
    expect_equal(nrow(plot$data), league$teams)
    expect_true(all(c("Team", "Position", "Probability") %in% names(plot$data)))
    
    # Verify probability constraints
    team_probs <- aggregate(plot$data$Probability, 
                           by = list(plot$data$Team), 
                           sum)
    expect_true(all(abs(team_probs$x - 1) < 0.01),
                info = "Each team's probabilities should sum to 1")
  }
})
```

## 3. Edge Case and Error Handling Tests

### A. Scheduler Edge Cases

```r
# tests/testthat/test-scheduler-edge-cases.R
test_that("Scheduler handles daylight saving time transitions", {
  # Mock time during DST transition
  with_mock_time("2024-03-31 02:30:00 Europe/Berlin", {
    # This time doesn't exist due to DST
    scheduler <- UpdateScheduler$new()
    
    # Should handle gracefully
    expect_true(is.logical(scheduler$is_update_time()))
    expect_false(is.na(scheduler$is_update_time()))
  })
  
  # Test fall back
  with_mock_time("2024-10-27 02:30:00 Europe/Berlin", {
    # This time occurs twice
    scheduler <- UpdateScheduler$new()
    
    # Should handle without duplication
    expect_true(is.logical(scheduler$is_update_time()))
  })
})

test_that("Scheduler prevents concurrent updates", {
  lock_manager <- LockManager$new()
  
  # First update acquires lock
  expect_true(lock_manager$acquire("league_update"))
  
  # Second update should fail
  expect_false(lock_manager$acquire("league_update"))
  
  # After release, should succeed
  lock_manager$release("league_update")
  expect_true(lock_manager$acquire("league_update"))
  
  # Cleanup
  lock_manager$release("league_update")
})

test_that("Scheduler recovers from failed updates", {
  # Simulate update failure
  with_mock(
    update_league = function(...) stop("API error"),
    {
      scheduler <- UpdateScheduler$new()
      
      # Should log error and continue
      expect_error(scheduler$run_update("Bundesliga"))
      
      # Scheduler should still be active
      expect_true(scheduler$is_active())
      
      # Next update should be attempted
      expect_true(!is.null(scheduler$next_update_time()))
    }
  )
})
```

### B. API Error Handling

```r
# tests/testthat/test-api-error-handling.R
test_that("API client implements exponential backoff", {
  attempts <- 0
  delays <- numeric()
  
  with_mock(
    httr::GET = function(...) {
      attempts <<- attempts + 1
      if (attempts < 3) {
        httr:::response(status_code = 429)  # Rate limited
      } else {
        httr:::response(status_code = 200)  # Success
      }
    },
    Sys.sleep = function(x) delays <<- c(delays, x),
    {
      result <- retrieve_fixtures_with_retry(78, max_attempts = 5)
      
      expect_equal(attempts, 3)
      expect_equal(length(delays), 2)  # Two retries
      expect_true(delays[2] > delays[1])  # Exponential backoff
    }
  )
})

test_that("API handles malformed responses", {
  test_cases <- list(
    list(name = "Missing response field", data = list()),
    list(name = "Empty response", data = list(response = list())),
    list(name = "Missing team IDs", data = list(response = list(list(
      fixture = list(status = list(short = "FT")),
      goals = list(home = 1, away = 0)
      # Missing teams field
    )))),
    list(name = "Invalid status", data = list(response = list(list(
      teams = list(home = list(id = 1), away = list(id = 2)),
      fixture = list(status = list(short = "INVALID")),
      goals = list(home = 1, away = 0)
    ))))
  )
  
  for (test_case in test_cases) {
    result <- safely_transform_data(test_case$data, create_test_elo_values())
    
    expect_true(!is.null(result),
                info = paste("Failed on:", test_case$name))
    expect_true(inherits(result, "data.frame") || inherits(result, "error"),
                info = paste("Should return data.frame or error for:", test_case$name))
  }
})
```

### C. Data Validation Edge Cases

```r
# tests/testthat/test-data-validation.R
test_that("System handles extreme ELO values", {
  # Test negative ELO
  expect_error(
    SpielNichtSimulieren(-100, 1500, 1, 0, 1.0, 65),
    "ELO.*negative|invalid.*ELO",
    ignore.case = TRUE
  )
  
  # Test very high ELO
  expect_warning(
    validate_elo_value(5000),
    "ELO value 5000 outside expected range"
  )
  
  # Test ELO difference clamping
  result <- calculate_elo_difference(3000, 1000)
  expect_lte(result, 400)  # Should be clamped to max 400
})

test_that("System handles edge case team counts", {
  # League with only 2 teams
  tiny_league <- create_test_season(2, 0.5)
  elo_values <- create_test_elo_values(2)
  
  result <- simulationsCPP(tiny_league, elo_values, 2, nrow(tiny_league), 100)
  expect_equal(ncol(result), 2)
  expect_equal(nrow(result), 100)
  
  # League with 30 teams (stress test)
  large_league <- create_test_season(30, 0.9)
  elo_values <- create_test_elo_values(30)
  
  # Should complete without error
  expect_silent({
    result <- simulationsCPP(large_league, elo_values, 30, nrow(large_league), 10)
  })
})

test_that("System handles mid-season edge cases", {
  # All games completed
  completed_season <- create_test_season(18, 1.0)
  elo_values <- create_test_elo_values(18)
  
  result <- simulationsCPP(completed_season, elo_values, 18, nrow(completed_season), 100)
  
  # All iterations should produce identical results
  for (i in 2:nrow(result)) {
    expect_equal(result[i,], result[1,],
                 info = "Completed season should have deterministic results")
  }
  
  # No games played
  fresh_season <- create_test_season(18, 0.0)
  
  result <- simulationsCPP(fresh_season, elo_values, 18, nrow(fresh_season), 100)
  
  # Results should vary between iterations
  expect_false(all(result[1,] == result[2,]),
               info = "Fresh season should have varying results")
})
```

## 4. Test Infrastructure and Coverage

### A. Test Coverage Requirements

```r
# tests/testthat/test-coverage-requirements.R
test_that("Critical functions have adequate test coverage", {
  skip_if_not_installed("covr")
  
  # Run coverage analysis
  cov <- covr::package_coverage(
    type = "tests",
    quiet = TRUE
  )
  
  # Overall coverage requirement
  total_coverage <- covr::percent_coverage(cov)
  expect_gte(total_coverage, 80,
             info = sprintf("Overall coverage: %.1f%% (minimum: 80%%)", total_coverage))
  
  # Critical files must have high coverage
  critical_files <- c(
    "RCode/simulationsCPP.R",
    "RCode/SaisonSimulierenCPP.R",
    "RCode/SpielNichtSimulieren.cpp",
    "RCode/Tabelle.R",
    "RCode/updateScheduler.R"
  )
  
  for (file in critical_files) {
    file_cov <- covr::file_coverage(cov, file)
    file_pct <- covr::percent_coverage(file_cov)
    
    expect_gte(file_pct, 95,
               info = sprintf("%s coverage: %.1f%% (minimum: 95%%)", file, file_pct))
  }
})
```

### B. Test Data Generators

```r
# tests/testthat/helper-test-generators.R

# Generate season with specific characteristics
generate_season_scenario <- function(n_teams, 
                                   played_games = NULL,
                                   specific_results = NULL,
                                   include_outliers = FALSE) {
  
  total_games <- n_teams * (n_teams - 1)
  
  if (is.null(played_games)) {
    played_games <- sample(0:total_games, 1)
  }
  
  # Create base fixture list
  fixtures <- expand.grid(
    HomeTeam = 1:n_teams,
    AwayTeam = 1:n_teams
  )
  fixtures <- fixtures[fixtures$HomeTeam != fixtures$AwayTeam, ]
  
  # Initialize results
  fixtures$HomeGoals <- NA
  fixtures$AwayGoals <- NA
  
  # Add played games
  if (played_games > 0) {
    set.seed(42)  # Reproducibility
    
    if (include_outliers) {
      # Include some extreme scores
      fixtures$HomeGoals[1:played_games] <- c(
        rpois(played_games - 5, 1.5),
        c(7, 0, 5, 0, 6)  # Outlier scores
      )[1:played_games]
      fixtures$AwayGoals[1:played_games] <- c(
        rpois(played_games - 5, 1.2),
        c(0, 5, 2, 4, 1)  # Outlier scores
      )[1:played_games]
    } else {
      fixtures$HomeGoals[1:played_games] <- rpois(played_games, 1.5)
      fixtures$AwayGoals[1:played_games] <- rpois(played_games, 1.2)
    }
  }
  
  # Apply specific results if provided
  if (!is.null(specific_results)) {
    for (result in specific_results) {
      idx <- which(fixtures$HomeTeam == result$home & 
                   fixtures$AwayTeam == result$away)
      if (length(idx) > 0) {
        fixtures$HomeGoals[idx] <- result$home_goals
        fixtures$AwayGoals[idx] <- result$away_goals
      }
    }
  }
  
  as.matrix(fixtures)
}

# Generate ELO values with specific patterns
generate_elo_scenario <- function(n_teams, 
                                pattern = c("normal", "dominant", "equal", "polarized")) {
  pattern <- match.arg(pattern)
  
  elo_values <- switch(pattern,
    normal = rnorm(n_teams, 1500, 150),
    dominant = c(rep(1800, 3), rep(1400, n_teams - 3)),  # Top 3 dominant
    equal = rep(1500, n_teams),  # All teams equal
    polarized = c(rep(1700, n_teams/2), rep(1300, n_teams/2))  # Two groups
  )
  
  # Ensure valid range
  elo_values <- pmax(1000, pmin(2000, elo_values))
  names(elo_values) <- 1:n_teams
  
  elo_values
}

# Generate API response with specific scenarios
generate_api_scenario <- function(scenario = c("normal", "error", "partial", "malformed")) {
  scenario <- match.arg(scenario)
  
  switch(scenario,
    normal = list(
      response = list(
        list(
          teams = list(
            home = list(id = 1, name = "Team 1"),
            away = list(id = 2, name = "Team 2")
          ),
          fixture = list(
            status = list(short = "FT"),
            date = "2024-01-15T15:00:00Z"
          ),
          goals = list(home = 2, away = 1)
        )
      )
    ),
    error = list(
      error = "API rate limit exceeded",
      status_code = 429
    ),
    partial = list(
      response = list(
        list(
          teams = list(home = list(id = 1), away = list(id = 2)),
          fixture = list(status = list(short = "FT")),
          goals = list(home = 2, away = NULL)  # Missing away goals
        )
      )
    ),
    malformed = list(
      response = "not a list"  # Completely wrong structure
    )
  )
}
```

## 5. Integration and Deployment Tests

### A. Docker Container Tests

```r
# tests/testthat/test-docker-deployment.R
test_that("Docker container starts with required environment variables", {
  skip_if_not(docker_available(), "Docker not available")
  
  # Test with missing environment variables
  expect_error(
    system2("docker", args = c("run", "league-simulator")),
    "RAPIDAPI_KEY.*required|environment.*variable",
    ignore.case = TRUE
  )
  
  # Test with all required variables
  env_args <- c(
    "-e", "RAPIDAPI_KEY=test_key",
    "-e", "SHINYAPPS_IO_SECRET=test_secret",
    "-e", "SEASON=2024",
    "-e", "DURATION=1"  # 1 minute for test
  )
  
  # Container should start successfully
  result <- system2("docker", 
                   args = c("run", "--rm", env_args, "league-simulator", "echo", "OK"),
                   stdout = TRUE)
  
  expect_equal(trimws(result), "OK")
})
```

### B. Multi-Environment Tests

```r
# tests/testthat/test-multi-environment.R
test_that("Code works across different R versions", {
  skip_if_not(Sys.getenv("TEST_MULTIPLE_R_VERSIONS") == "true")
  
  r_versions <- c("4.2.0", "4.3.0", "4.4.0")
  
  for (version in r_versions) {
    # Run basic functionality test
    result <- test_with_r_version(version, {
      source("RCode/simulationsCPP.R")
      season <- create_test_season(4, 0.5)
      elo <- create_test_elo_values(4)
      simulationsCPP(season, elo, 4, nrow(season), 10)
    })
    
    expect_true(!is.null(result),
                info = sprintf("Failed on R version %s", version))
  }
})
```

## Test Execution Guidelines

### Running Tests

```r
# Run all tests
testthat::test_local()

# Run only performance tests
Sys.setenv(RUN_PERFORMANCE_TESTS = "true")
testthat::test_file("tests/testthat/test-performance-empirical.R")

# Run with coverage
covr::package_coverage()

# Run specific test suites
testthat::test_dir("tests/testthat", filter = "performance")
testthat::test_dir("tests/testthat", filter = "edge-case")
```

### CI/CD Integration

```yaml
# .github/workflows/tests.yml
name: Run Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        r-version: ['4.2.0', '4.3.0', '4.4.0']
    
    steps:
    - uses: actions/checkout@v3
    - uses: r-lib/actions/setup-r@v2
      with:
        r-version: ${{ matrix.r-version }}
    
    - name: Install dependencies
      run: |
        install.packages(c("testthat", "covr", "microbenchmark"))
        install.packages(readLines("packagelist.txt"))
    
    - name: Run tests
      run: |
        testthat::test_local()
      env:
        RUN_PERFORMANCE_TESTS: ${{ matrix.os == 'ubuntu-latest' && matrix.r-version == '4.4.0' }}
    
    - name: Upload coverage
      if: matrix.os == 'ubuntu-latest' && matrix.r-version == '4.4.0'
      run: covr::codecov()
```

## Success Metrics

1. **Performance**: All tests pass with <10% deviation from empirical baselines
2. **Scaling**: O(N) scaling verified for both iterations and games
3. **Coverage**: >80% overall, >95% for critical components
4. **Reliability**: All edge cases handled gracefully
5. **Portability**: Tests pass on all supported platforms/R versions

These comprehensive test specifications ensure the League Simulator is robust, performant, and maintainable.