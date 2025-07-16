# Baseline Performance Measurements for League Simulator
# This script runs empirical performance measurements to establish baselines

library(microbenchmark)
library(jsonlite)
library(ggplot2)

# Source required functions
source("RCode/simulationsCPP.R")
source("RCode/SaisonSimulierenCPP.R")
source("RCode/SpielCPP.R")
source("RCode/Tabelle.R")
# Load Rcpp library first
library(Rcpp)
# Compile and load C++ functions
sourceCpp("RCode/SpielNichtSimulieren.cpp")

# Create output directory
dir.create("tests/performance/baselines", recursive = TRUE, showWarnings = FALSE)

# Function to get system info
get_system_info <- function() {
  list(
    platform = Sys.info()["sysname"],
    release = Sys.info()["release"],
    machine = Sys.info()["machine"],
    cpu_cores = parallel::detectCores(),
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    timestamp = Sys.time()
  )
}

# Function to create realistic test data matching the expected format
create_realistic_season <- function(n_teams = 18, games_played_pct = 0.5) {
  teams <- paste0("Team_", 1:n_teams)
  n_rounds <- (n_teams - 1) * 2
  
  # Create full fixture list with team numbers (not names)
  fixtures <- expand.grid(
    HomeTeam = 1:n_teams,
    AwayTeam = 1:n_teams,
    stringsAsFactors = FALSE
  )
  fixtures <- fixtures[fixtures$HomeTeam != fixtures$AwayTeam, ]
  
  # Add results for played games
  n_played <- floor(nrow(fixtures) * games_played_pct)
  fixtures$HomeGoals <- NA
  fixtures$AwayGoals <- NA
  
  if (n_played > 0) {
    fixtures$HomeGoals[1:n_played] <- rpois(n_played, 1.5)
    fixtures$AwayGoals[1:n_played] <- rpois(n_played, 1.2)
  }
  
  # Convert to matrix as expected by simulationsCPP
  as.matrix(fixtures)
}

# Function to create realistic ELO data
create_realistic_elo <- function(n_teams = 18) {
  # ELO ratings normally distributed around 1500
  elo_values <- rnorm(n_teams, mean = 1500, sd = 150)
  elo_values <- pmax(1000, pmin(2000, elo_values)) # Clamp to reasonable range
  
  # Return as named vector (team numbers as names)
  names(elo_values) <- 1:n_teams
  return(elo_values)
}

# Run performance measurements
cat("Running baseline performance measurements...\n\n")

# Store all results
results <- list()

# Test 1: Iteration scaling (Bundesliga-sized league, 50% season complete)
cat("Test 1: Iteration scaling (18 teams, 50% season)\n")
n_teams <- 18
season_data <- create_realistic_season(n_teams, 0.5)
elo_data <- create_realistic_elo(n_teams)

iteration_counts <- c(10, 100, 1000, 5000, 10000)
iteration_results <- list()

for (n_iter in iteration_counts) {
  cat(sprintf("  Running %d iterations...", n_iter))
  
  bench <- microbenchmark(
    simulationsCPP(season = season_data, 
                   ELOValue = elo_data, 
                   numberTeams = n_teams, 
                   numberGames = nrow(season_data), 
                   iterations = n_iter),
    times = ifelse(n_iter <= 100, 10, ifelse(n_iter <= 1000, 5, 3)),
    unit = "ms"
  )
  
  iteration_results[[as.character(n_iter)]] <- list(
    iterations = n_iter,
    median_ms = median(bench$time) / 1e6,
    mean_ms = mean(bench$time) / 1e6,
    min_ms = min(bench$time) / 1e6,
    max_ms = max(bench$time) / 1e6,
    sd_ms = sd(bench$time) / 1e6
  )
  
  cat(sprintf(" median: %.1f ms\n", median(bench$time) / 1e6))
}

results$iteration_scaling <- iteration_results

# Test 2: Game count scaling (1000 iterations, varying season completion)
cat("\nTest 2: Game count scaling (18 teams, 1000 iterations)\n")
completion_levels <- c(0.0, 0.25, 0.5, 0.75, 0.9)
game_results <- list()

for (pct in completion_levels) {
  cat(sprintf("  Season %.0f%% complete...", pct * 100))
  
  season_data <- create_realistic_season(n_teams, pct)
  games_to_simulate <- sum(is.na(season_data[,3]))
  
  bench <- microbenchmark(
    simulationsCPP(season = season_data, 
                   ELOValue = elo_data, 
                   numberTeams = n_teams, 
                   numberGames = nrow(season_data), 
                   iterations = 1000),
    times = 5,
    unit = "ms"
  )
  
  game_results[[as.character(pct)]] <- list(
    completion_pct = pct,
    games_to_simulate = games_to_simulate,
    median_ms = median(bench$time) / 1e6,
    mean_ms = mean(bench$time) / 1e6,
    min_ms = min(bench$time) / 1e6,
    max_ms = max(bench$time) / 1e6,
    sd_ms = sd(bench$time) / 1e6
  )
  
  cat(sprintf(" median: %.1f ms (%d games)\n", median(bench$time) / 1e6, games_to_simulate))
}

results$game_scaling <- game_results

# Test 3: League size comparison (1000 iterations, 50% complete)
cat("\nTest 3: League size comparison (1000 iterations, 50% season)\n")
league_configs <- list(
  bundesliga = list(teams = 18, name = "Bundesliga (18 teams)"),
  dritte_liga = list(teams = 20, name = "3. Liga (20 teams)")
)

league_results <- list()

for (league in names(league_configs)) {
  config <- league_configs[[league]]
  cat(sprintf("  %s...", config$name))
  
  season_data <- create_realistic_season(config$teams, 0.5)
  elo_data <- create_realistic_elo(config$teams)
  
  bench <- microbenchmark(
    simulationsCPP(season = season_data, 
                   ELOValue = elo_data, 
                   numberTeams = config$teams, 
                   numberGames = nrow(season_data), 
                   iterations = 1000),
    times = 5,
    unit = "ms"
  )
  
  league_results[[league]] <- list(
    league = config$name,
    n_teams = config$teams,
    total_games = nrow(season_data),
    games_to_simulate = sum(is.na(season_data[,3])),
    median_ms = median(bench$time) / 1e6,
    mean_ms = mean(bench$time) / 1e6,
    min_ms = min(bench$time) / 1e6,
    max_ms = max(bench$time) / 1e6,
    sd_ms = sd(bench$time) / 1e6
  )
  
  cat(sprintf(" median: %.1f ms\n", median(bench$time) / 1e6))
}

results$league_comparison <- league_results

# Test 4: Component breakdown (1000 iterations)
cat("\nTest 4: Component performance breakdown\n")
season_data <- create_realistic_season(18, 0.5)
elo_data <- create_realistic_elo(18)

# Test individual components
cat("  ELO calculation...")
bench_elo <- microbenchmark(
  SpielNichtSimulieren(1500, 1400, 2, 1, 1.0, 65),
  times = 10000,
  unit = "ns"
)
cat(sprintf(" median: %.1f ns\n", median(bench_elo$time)))

cat("  Single season simulation...")
bench_season <- microbenchmark(
  SaisonSimulierenCPP(Spielplan = season_data, 
                      ELOWerte = elo_data,
                      AnzahlTeams = 18,
                      AnzahlSpiele = nrow(season_data)),
  times = 100,
  unit = "us"
)
cat(sprintf(" median: %.1f µs\n", median(bench_season$time) / 1000))

cat("  Table calculation...")
# Create a season with some results for table calculation
table_data <- create_realistic_season(18, 1.0)
table_df <- data.frame(
  HomeTeam = table_data[,1],
  AwayTeam = table_data[,2],
  HomeGoals = table_data[,3],
  AwayGoals = table_data[,4]
)
bench_table <- microbenchmark(
  Tabelle(table_df),
  times = 1000,
  unit = "us"
)
cat(sprintf(" median: %.1f µs\n", median(bench_table$time) / 1000))

results$components <- list(
  elo_calculation_ns = median(bench_elo$time),
  season_simulation_us = median(bench_season$time) / 1000,
  table_calculation_us = median(bench_table$time) / 1000
)

# Calculate scaling factors
cat("\nScaling Analysis:\n")

# Iteration scaling factor
iter_100 <- results$iteration_scaling$`100`$median_ms
iter_1000 <- results$iteration_scaling$`1000`$median_ms
iter_10000 <- results$iteration_scaling$`10000`$median_ms

scaling_100_to_1000 <- iter_1000 / iter_100
scaling_1000_to_10000 <- iter_10000 / iter_1000

cat(sprintf("  100 -> 1000 iterations: %.2fx (expected: ~10x)\n", scaling_100_to_1000))
cat(sprintf("  1000 -> 10000 iterations: %.2fx (expected: ~10x)\n", scaling_1000_to_10000))

# Game scaling factor
games_0 <- results$game_scaling$`0`$median_ms
games_50 <- results$game_scaling$`0.5`$median_ms
games_90 <- results$game_scaling$`0.9`$median_ms

cat(sprintf("\n  100%% games vs 50%% games: %.2fx faster\n", games_0 / games_50))
cat(sprintf("  100%% games vs 10%% games: %.2fx faster\n", games_0 / games_90))

# Save results
results$system_info <- get_system_info()
results$scaling_analysis <- list(
  scaling_100_to_1000 = scaling_100_to_1000,
  scaling_1000_to_10000 = scaling_1000_to_10000,
  scaling_is_linear = abs(scaling_100_to_1000 - 10) < 2 && abs(scaling_1000_to_10000 - 10) < 2,
  game_scaling_50pct = games_0 / games_50,
  game_scaling_90pct = games_0 / games_90
)

# Write baseline file
baseline_file <- sprintf("tests/performance/baselines/baseline_%s.json", 
                        format(Sys.time(), "%Y%m%d_%H%M%S"))

write_json(results, baseline_file, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\nBaseline results saved to: %s\n", baseline_file))

# Create visualization
library(ggplot2)

# Plot iteration scaling
iter_df <- do.call(rbind, lapply(results$iteration_scaling, as.data.frame))
iter_plot <- ggplot(iter_df, aes(x = iterations, y = median_ms)) +
  geom_line() +
  geom_point() +
  scale_x_log10() +
  scale_y_log10() +
  labs(title = "Performance Scaling with Iterations",
       x = "Number of Iterations",
       y = "Median Time (ms)") +
  theme_minimal()

ggsave("tests/performance/baselines/iteration_scaling.png", iter_plot, width = 8, height = 6)

# Plot game count scaling
game_df <- do.call(rbind, lapply(results$game_scaling, as.data.frame))
game_plot <- ggplot(game_df, aes(x = games_to_simulate, y = median_ms)) +
  geom_line() +
  geom_point() +
  labs(title = "Performance Scaling with Games to Simulate",
       x = "Number of Games to Simulate",
       y = "Median Time (ms)") +
  theme_minimal()

ggsave("tests/performance/baselines/game_scaling.png", game_plot, width = 8, height = 6)

cat("\nBaseline measurement complete!\n")