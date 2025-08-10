#!/usr/bin/env Rscript

# Script to extract test data from R implementation for Rust testing
library(jsonlite)
library(Rcpp)

# Source the R/C++ implementations
sourceCpp("RCode/SpielNichtSimulieren.cpp")
source("RCode/SpielCPP.R")

# Create test data directory if it doesn't exist
dir.create("league-simulator-rust/test_data", showWarnings = FALSE, recursive = TRUE)

# 1. Extract ELO calculation test cases
elo_test_cases <- list(
  test_cases = list(
    # Home win test case
    list(
      name = "home_win_equal_elo",
      input = list(
        elo_home = 1500,
        elo_away = 1500,
        goals_home = 2,
        goals_away = 1,
        mod_factor = 40,
        home_advantage = 0
      ),
      expected = SpielNichtSimulieren(1500, 1500, 2, 1, 40, 0)
    ),
    
    # Away win test case
    list(
      name = "away_win_equal_elo",
      input = list(
        elo_home = 1500,
        elo_away = 1500,
        goals_home = 0,
        goals_away = 2,
        mod_factor = 40,
        home_advantage = 0
      ),
      expected = SpielNichtSimulieren(1500, 1500, 0, 2, 40, 0)
    ),
    
    # Draw test case
    list(
      name = "draw_equal_elo",
      input = list(
        elo_home = 1500,
        elo_away = 1500,
        goals_home = 1,
        goals_away = 1,
        mod_factor = 40,
        home_advantage = 0
      ),
      expected = SpielNichtSimulieren(1500, 1500, 1, 1, 40, 0)
    ),
    
    # Stronger home team wins
    list(
      name = "stronger_home_wins",
      input = list(
        elo_home = 1700,
        elo_away = 1300,
        goals_home = 3,
        goals_away = 0,
        mod_factor = 40,
        home_advantage = 0
      ),
      expected = SpielNichtSimulieren(1700, 1300, 3, 0, 40, 0)
    ),
    
    # Underdog away team wins
    list(
      name = "underdog_away_wins",
      input = list(
        elo_home = 1700,
        elo_away = 1300,
        goals_home = 1,
        goals_away = 2,
        mod_factor = 40,
        home_advantage = 0
      ),
      expected = SpielNichtSimulieren(1700, 1300, 1, 2, 40, 0)
    ),
    
    # Home advantage test
    list(
      name = "with_home_advantage",
      input = list(
        elo_home = 1500,
        elo_away = 1500,
        goals_home = 2,
        goals_away = 1,
        mod_factor = 20,
        home_advantage = 65
      ),
      expected = SpielNichtSimulieren(1500, 1500, 2, 1, 20, 65)
    ),
    
    # Large goal difference
    list(
      name = "large_goal_difference",
      input = list(
        elo_home = 1500,
        elo_away = 1500,
        goals_home = 5,
        goals_away = 0,
        mod_factor = 40,
        home_advantage = 0
      ),
      expected = SpielNichtSimulieren(1500, 1500, 5, 0, 40, 0)
    ),
    
    # Different mod factors
    list(
      name = "different_mod_factor",
      input = list(
        elo_home = 1600,
        elo_away = 1400,
        goals_home = 2,
        goals_away = 2,
        mod_factor = 20,
        home_advantage = 0
      ),
      expected = SpielNichtSimulieren(1600, 1400, 2, 2, 20, 0)
    )
  )
)

# Save ELO test cases
write_json(elo_test_cases, "league-simulator-rust/test_data/elo_test_cases.json", 
           auto_unbox = TRUE, pretty = TRUE, digits = 10)

# 2. Extract match simulation test cases (with seeds for reproducibility)
set.seed(42)
match_sim_cases <- list(
  test_cases = list(
    list(
      name = "equal_teams_simulation",
      input = list(
        elo_home = 1500,
        elo_away = 1500,
        mod_factor = 20,
        home_advantage = 65,
        tore_slope = 0.0017854953143549,
        tore_intercept = 1.3218390804597700,
        random_home = 0.5,
        random_away = 0.5
      ),
      expected = SpielCPP(1500, 1500, ZufallHeim = 0.5, ZufallGast = 0.5,
                          ModFaktor = 20, Heimvorteil = 65, Simulieren = TRUE)
    ),
    
    list(
      name = "strong_home_simulation",
      input = list(
        elo_home = 1800,
        elo_away = 1200,
        mod_factor = 20,
        home_advantage = 65,
        tore_slope = 0.0017854953143549,
        tore_intercept = 1.3218390804597700,
        random_home = 0.7,
        random_away = 0.3
      ),
      expected = SpielCPP(1800, 1200, ZufallHeim = 0.7, ZufallGast = 0.3,
                          ModFaktor = 20, Heimvorteil = 65, Simulieren = TRUE)
    )
  )
)

write_json(match_sim_cases, "league-simulator-rust/test_data/match_simulation_cases.json",
           auto_unbox = TRUE, pretty = TRUE, digits = 10)

# 3. Create sample season data
sample_season <- data.frame(
  team_home = c(1, 2, 3, 1, 2, 3),
  team_away = c(2, 3, 1, 3, 1, 2),
  goals_home = c(2, 1, NA, NA, NA, NA),
  goals_away = c(1, 1, NA, NA, NA, NA)
)

initial_elos <- c(1500, 1600, 1400)

season_test_data <- list(
  schedule = sample_season,
  initial_elos = initial_elos,
  number_teams = 3,
  number_games = 6,
  mod_factor = 20,
  home_advantage = 65
)

write_json(season_test_data, "league-simulator-rust/test_data/season_test_data.json",
           auto_unbox = TRUE, pretty = TRUE)

# 4. Statistical distribution parameters for validation
distribution_params <- list(
  poisson_lambda_home_equal = 1.3218390804597700 + 65 * 0.0017854953143549,
  poisson_lambda_away_equal = 1.3218390804597700 - 65 * 0.0017854953143549,
  elo_k_factor = 400,
  goal_mod_sqrt = TRUE,
  iterations_default = 10000
)

write_json(distribution_params, "league-simulator-rust/test_data/distribution_params.json",
           auto_unbox = TRUE, pretty = TRUE)

cat("Test data extracted successfully to league-simulator-rust/test_data/\n")
cat("Files created:\n")
cat("  - elo_test_cases.json\n")
cat("  - match_simulation_cases.json\n")
cat("  - season_test_data.json\n")
cat("  - distribution_params.json\n")