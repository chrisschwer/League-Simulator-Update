# Empirical Baseline Performance Measurements
# Focused script to measure actual performance characteristics

library(microbenchmark)
library(jsonlite)

# Source required functions
source("RCode/simulationsCPP.R")
source("RCode/SaisonSimulierenCPP.R")
source("RCode/SpielCPP.R")
source("RCode/Tabelle.R")
library(Rcpp)
sourceCpp("RCode/SpielNichtSimulieren.cpp")

# Create output directory
dir.create("tests/performance/baselines", recursive = TRUE, showWarnings = FALSE)

# Helper to create test season data
create_test_season <- function(n_teams, pct_complete) {
  total_games <- n_teams * (n_teams - 1)
  games_played <- floor(total_games * pct_complete)
  
  # Create all possible fixtures
  fixtures <- expand.grid(
    HomeTeam = 1:n_teams,
    AwayTeam = 1:n_teams
  )
  fixtures <- fixtures[fixtures$HomeTeam != fixtures$AwayTeam, ]
  
  # Add results for played games
  fixtures$HomeGoals <- NA
  fixtures$AwayGoals <- NA
  
  if (games_played > 0) {
    set.seed(42) # For reproducibility
    fixtures$HomeGoals[1:games_played] <- rpois(games_played, 1.5)
    fixtures$AwayGoals[1:games_played] <- rpois(games_played, 1.2)
  }
  
  as.matrix(fixtures)
}

# Create ELO values
create_test_elo <- function(n_teams) {
  set.seed(42)
  elo_values <- rnorm(n_teams, 1500, 150)
  elo_values <- pmax(1000, pmin(2000, elo_values))
  names(elo_values) <- 1:n_teams
  elo_values
}

cat("=== EMPIRICAL BASELINE MEASUREMENTS ===\n\n")

# Test 1: Measure actual scaling with iterations
cat("1. ITERATION SCALING TEST (18 teams, 50% season complete)\n")
season_18 <- create_test_season(18, 0.5)
elo_18 <- create_test_elo(18)
games_to_sim <- sum(is.na(season_18[,3]))
cat(sprintf("   Games to simulate: %d\n\n", games_to_sim))

iter_tests <- c(10, 100, 1000, 10000)
iter_results <- list()

for (n in iter_tests) {
  cat(sprintf("   Testing %d iterations...", n))
  
  # Run fewer times for larger iterations
  times <- if(n <= 100) 5 else if(n <= 1000) 3 else 1
  
  timing <- microbenchmark(
    simulationsCPP(
      season = season_18,
      ELOValue = elo_18,
      numberTeams = 18,
      numberGames = nrow(season_18),
      iterations = n
    ),
    times = times
  )
  
  med_time <- median(timing$time) / 1e6  # Convert to ms
  iter_results[[as.character(n)]] <- med_time
  cat(sprintf(" %.1f ms\n", med_time))
}

# Calculate scaling factors
cat("\n   Scaling Analysis:\n")
scale_10_100 <- iter_results[["100"]] / iter_results[["10"]]
scale_100_1000 <- iter_results[["1000"]] / iter_results[["100"]]
scale_1000_10000 <- iter_results[["10000"]] / iter_results[["1000"]]

cat(sprintf("   10 -> 100: %.1fx (expected: 10x)\n", scale_10_100))
cat(sprintf("   100 -> 1000: %.1fx (expected: 10x)\n", scale_100_1000))
cat(sprintf("   1000 -> 10000: %.1fx (expected: 10x)\n", scale_1000_10000))

# Test 2: Measure game count impact
cat("\n2. GAME COUNT IMPACT TEST (18 teams, 1000 iterations)\n")
completion_levels <- c(0, 0.25, 0.5, 0.75, 0.9)
game_results <- list()

for (pct in completion_levels) {
  season <- create_test_season(18, pct)
  games_remaining <- sum(is.na(season[,3]))
  
  cat(sprintf("   %.0f%% complete (%d games to simulate)...", pct * 100, games_remaining))
  
  timing <- microbenchmark(
    simulationsCPP(
      season = season,
      ELOValue = elo_18,
      numberTeams = 18,
      numberGames = nrow(season),
      iterations = 1000
    ),
    times = 3
  )
  
  med_time <- median(timing$time) / 1e6
  game_results[[as.character(pct)]] <- list(
    games = games_remaining,
    time_ms = med_time
  )
  cat(sprintf(" %.1f ms\n", med_time))
}

# Test 3: League size comparison
cat("\n3. LEAGUE SIZE COMPARISON (1000 iterations, 50% complete)\n")

# Test Bundesliga (18 teams)
cat("   Bundesliga (18 teams)...")
timing_bl <- microbenchmark(
  simulationsCPP(
    season = season_18,
    ELOValue = elo_18,
    numberTeams = 18,
    numberGames = nrow(season_18),
    iterations = 1000
  ),
  times = 3
)
bl_time <- median(timing_bl$time) / 1e6
cat(sprintf(" %.1f ms\n", bl_time))

# Test 3. Liga (20 teams)
cat("   3. Liga (20 teams)...")
season_20 <- create_test_season(20, 0.5)
elo_20 <- create_test_elo(20)
timing_3l <- microbenchmark(
  simulationsCPP(
    season = season_20,
    ELOValue = elo_20,
    numberTeams = 20,
    numberGames = nrow(season_20),
    iterations = 1000
  ),
  times = 3
)
liga3_time <- median(timing_3l$time) / 1e6
cat(sprintf(" %.1f ms\n", liga3_time))

cat(sprintf("\n   20-team league is %.1fx slower than 18-team league\n", liga3_time / bl_time))

# Test 4: Component performance
cat("\n4. COMPONENT PERFORMANCE\n")

# ELO calculation
cat("   Single ELO calculation...")
elo_timing <- microbenchmark(
  SpielNichtSimulieren(1500, 1400, 2, 1, 1.0, 65),
  times = 10000
)
elo_time_ns <- median(elo_timing$time)
cat(sprintf(" %.0f ns\n", elo_time_ns))

# Full match simulation (including random number generation)
cat("   Single match simulation...")
match_timing <- microbenchmark(
  SpielCPP(1500, 1400, runif(1), runif(1), 20, 65, TRUE),
  times = 1000
)
match_time_us <- median(match_timing$time) / 1000
cat(sprintf(" %.1f µs\n", match_time_us))

# Table calculation
cat("   Table calculation (18 teams)...")
completed_season <- create_test_season(18, 1.0)
table_df <- data.frame(
  HomeTeam = completed_season[,1],
  AwayTeam = completed_season[,2],
  HomeGoals = completed_season[,3],
  AwayGoals = completed_season[,4]
)
table_timing <- microbenchmark(
  Tabelle(table_df, numberTeams = 18),
  times = 100
)
table_time_us <- median(table_timing$time) / 1000
cat(sprintf(" %.1f µs\n", table_time_us))

# Save results
results <- list(
  iteration_scaling = iter_results,
  scaling_factors = list(
    scale_10_100 = scale_10_100,
    scale_100_1000 = scale_100_1000,
    scale_1000_10000 = scale_1000_10000
  ),
  game_impact = game_results,
  league_comparison = list(
    bundesliga_ms = bl_time,
    liga3_ms = liga3_time,
    ratio = liga3_time / bl_time
  ),
  component_performance = list(
    elo_calculation_ns = elo_time_ns,
    match_simulation_us = match_time_us,
    table_calculation_us = table_time_us
  ),
  system_info = list(
    platform = Sys.info()["sysname"],
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    timestamp = Sys.time()
  )
)

# Write results
output_file <- "tests/performance/baselines/empirical_baseline.json"
write_json(results, output_file, pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n\nResults saved to: %s\n", output_file))

# Summary
cat("\n=== PERFORMANCE SUMMARY ===\n")
cat(sprintf("- 10,000 iterations take ~%.1f seconds\n", iter_results[["10000"]] / 1000))
cat(sprintf("- Scaling is approximately %.1fx per 10x iterations\n", mean(c(scale_100_1000, scale_1000_10000))))
cat(sprintf("- Each game adds ~%.1f ms to 1000-iteration simulation\n", 
            (game_results[["0"]]$time_ms - game_results[["0.5"]]$time_ms) / 
            (game_results[["0"]]$games - game_results[["0.5"]]$games)))
cat(sprintf("- Single ELO calculation: ~%.0f ns\n", elo_time_ns))
cat(sprintf("- Single match simulation: ~%.1f µs\n", match_time_us))