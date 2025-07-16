# ELO-based Mock Data Generator for Integration Tests
# This file implements realistic match result generation based on ELO ratings,
# matching the actual simulation logic from SpielCPP.R

#' Generate ELO-based match results
#' 
#' @param teams Data frame with team names and initial ELO ratings
#' @param fixtures Data frame with match fixtures (home, away columns)
#' @param seed Random seed for reproducibility
#' @return List with match results and final ELO ratings
generate_elo_based_results <- function(teams, fixtures, seed = 123) {
  set.seed(seed)
  results <- list()
  
  # Copy initial ELOs to track changes
  current_elos <- setNames(teams$ELO, teams$Team)
  
  # Constants from the actual simulator
  HOME_ADVANTAGE <- 65
  TORE_SLOPE <- 0.0017854953143549
  TORE_INTERCEPT <- 1.3218390804597700
  ELO_MODIFICATOR <- 20
  
  for (i in seq_len(nrow(fixtures))) {
    fixture <- fixtures[i, ]
    
    # Get current ELOs
    elo_home <- current_elos[fixture$home]
    elo_away <- current_elos[fixture$away]
    
    # Calculate ELO delta with home advantage
    elo_delta <- elo_home + HOME_ADVANTAGE - elo_away
    
    # Calculate expected goals using actual simulator parameters
    lambda_home <- max(elo_delta * TORE_SLOPE + TORE_INTERCEPT, 0.001)
    lambda_away <- max(-elo_delta * TORE_SLOPE + TORE_INTERCEPT, 0.001)
    
    # Generate goals from Poisson distribution
    # Using quantile function with uniform random values for deterministic results
    home_goals <- qpois(runif(1), lambda = lambda_home)
    away_goals <- qpois(runif(1), lambda = lambda_away)
    
    # Calculate match result for ELO update
    if (home_goals > away_goals) {
      result <- 1  # Home win
    } else if (home_goals < away_goals) {
      result <- 0  # Away win
    } else {
      result <- 0.5  # Draw
    }
    
    # Calculate ELO probability (expected result)
    elo_prob <- 1 / (1 + 10^(-elo_delta/400))
    
    # Calculate goal difference modifier
    goal_diff <- abs(home_goals - away_goals)
    goal_mod <- sqrt(max(goal_diff, 1))
    
    # Update ELOs using actual formula
    elo_change <- (result - elo_prob) * goal_mod * ELO_MODIFICATOR
    
    current_elos[fixture$home] <- current_elos[fixture$home] + elo_change
    current_elos[fixture$away] <- current_elos[fixture$away] - elo_change
    
    # Store result
    results[[i]] <- list(
      home = fixture$home,
      away = fixture$away,
      home_goals = home_goals,
      away_goals = away_goals,
      home_elo_before = elo_home,
      away_elo_before = elo_away,
      home_elo_after = current_elos[fixture$home],
      away_elo_after = current_elos[fixture$away],
      elo_change = elo_change,
      match_date = fixture$date
    )
  }
  
  return(list(
    results = results,
    final_elos = current_elos,
    initial_elos = setNames(teams$ELO, teams$Team)
  ))
}

#' Generate a complete season fixture list
#' 
#' @param team_names Vector of team names
#' @return Data frame with all fixtures (double round-robin)
generate_season_fixtures <- function(team_names) {
  n_teams <- length(team_names)
  fixtures <- data.frame(
    home = character(),
    away = character(),
    date = as.Date(character()),
    stringsAsFactors = FALSE
  )
  
  # Generate double round-robin (each team plays each other twice)
  match_id <- 1
  start_date <- as.Date("2024-08-01")
  
  # First half of season
  for (i in 1:(n_teams - 1)) {
    for (j in (i + 1):n_teams) {
      fixtures <- rbind(fixtures, data.frame(
        home = team_names[i],
        away = team_names[j],
        date = start_date + (match_id %/% 9) * 7,  # 9 games per matchday
        stringsAsFactors = FALSE
      ))
      match_id <- match_id + 1
    }
  }
  
  # Second half of season (reverse fixtures)
  for (i in 1:(n_teams - 1)) {
    for (j in (i + 1):n_teams) {
      fixtures <- rbind(fixtures, data.frame(
        home = team_names[j],
        away = team_names[i],
        date = start_date + (match_id %/% 9) * 7,
        stringsAsFactors = FALSE
      ))
      match_id <- match_id + 1
    }
  }
  
  return(fixtures)
}

#' Validate ELO consistency
#' 
#' @param initial_elos Named vector of initial ELO ratings
#' @param final_elos Named vector of final ELO ratings
#' @param tolerance Acceptable difference in average ELO
#' @return TRUE if ELOs are consistent (zero-sum maintained)
validate_elo_consistency <- function(initial_elos, final_elos, tolerance = 1) {
  initial_avg <- mean(initial_elos)
  final_avg <- mean(final_elos)
  
  # ELO should be zero-sum (average remains constant)
  return(abs(initial_avg - final_avg) < tolerance)
}

#' Generate match results for partial season
#' 
#' @param teams Data frame with teams and ELOs
#' @param matchdays Number of matchdays to simulate
#' @param seed Random seed
#' @return List with partial season results
generate_partial_season <- function(teams, matchdays = 10, seed = 123) {
  fixtures <- generate_season_fixtures(teams$Team)
  matches_per_matchday <- nrow(teams) / 2
  
  # Select fixtures for specified matchdays
  n_matches <- matchdays * matches_per_matchday
  partial_fixtures <- fixtures[1:n_matches, ]
  
  return(generate_elo_based_results(teams, partial_fixtures, seed))
}

#' Create realistic test team data
#' 
#' @param n_teams Number of teams (default 18 for Bundesliga)
#' @return Data frame with team names and realistic ELO distribution
create_test_teams <- function(n_teams = 18) {
  # Create realistic ELO distribution
  # Top teams: 1700-1800
  # Mid teams: 1400-1600
  # Bottom teams: 1200-1400
  
  team_names <- paste0("Team", sprintf("%02d", 1:n_teams))
  
  # Generate realistic ELO distribution
  elos <- c(
    runif(3, 1700, 1800),  # Top 3 teams
    runif(6, 1500, 1650),  # Upper mid-table
    runif(6, 1350, 1500),  # Lower mid-table
    runif(3, 1200, 1350)   # Bottom 3 teams
  )
  
  # Ensure average is exactly 1500
  elos <- elos - mean(elos) + 1500
  
  return(data.frame(
    Team = team_names,
    ELO = round(elos),
    stringsAsFactors = FALSE
  ))
}