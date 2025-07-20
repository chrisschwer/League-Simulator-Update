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
  # Increase slope for more varied results in tests
  TORE_SLOPE <- 0.002  # Slightly higher for more variation
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
    # Add more randomness to reduce correlation
    home_goals <- rpois(1, lambda = lambda_home)
    away_goals <- rpois(1, lambda = lambda_away)
    
    # Add occasional upsets (10% chance)
    if (runif(1) < 0.1) {
      # Swap results occasionally to create upsets
      temp <- home_goals
      home_goals <- away_goals
      away_goals <- temp
    }
    
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
  
  # Only works for even number of teams
  if (n_teams %% 2 != 0) {
    stop("This function requires an even number of teams")
  }
  
  fixtures <- data.frame(
    home = character(),
    away = character(),
    date = as.Date(character()),
    stringsAsFactors = FALSE
  )
  
  start_date <- as.Date("2024-08-01")
  
  # Define the 18-team round-robin schedule (rounds 1-17)
  # Each row is a round, each pair is a match (home - away)
  schedule <- list(
    list(c(1,2), c(3,4), c(5,6), c(7,8), c(9,10), c(11,12), c(13,14), c(15,16), c(17,18)),
    list(c(7,14), c(9,16), c(18,11), c(2,13), c(15,4), c(17,6), c(1,8), c(3,10), c(12,5)),
    list(c(8,13), c(15,10), c(17,12), c(14,1), c(16,3), c(18,5), c(2,7), c(4,9), c(6,11)),
    list(c(15,18), c(17,2), c(1,4), c(3,6), c(5,8), c(7,10), c(12,9), c(14,11), c(16,13)),
    list(c(10,17), c(12,1), c(14,3), c(5,16), c(18,7), c(9,2), c(4,11), c(13,6), c(15,8)),
    list(c(6,9), c(11,8), c(10,13), c(15,12), c(17,14), c(16,1), c(18,3), c(5,2), c(7,4)),
    list(c(17,15), c(4,5), c(12,18), c(10,2), c(7,11), c(3,9), c(13,1), c(16,8), c(14,6)),
    list(c(3,7), c(6,12), c(2,14), c(16,4), c(13,15), c(10,11), c(8,18), c(9,1), c(5,17)),
    list(c(4,14), c(13,11), c(9,5), c(6,18), c(1,17), c(12,8), c(16,10), c(7,15), c(2,3)),
    list(c(13,3), c(5,7), c(16,17), c(12,10), c(8,6), c(2,4), c(9,15), c(18,14), c(11,1)),
    list(c(5,1), c(2,18), c(8,10), c(9,7), c(12,13), c(14,16), c(11,17), c(6,4), c(3,15)),
    list(c(9,11), c(1,15), c(6,7), c(8,14), c(3,5), c(13,17), c(10,4), c(2,12), c(18,16)),
    list(c(14,10), c(7,17), c(13,9), c(11,3), c(4,12), c(5,15), c(6,16), c(1,18), c(8,2)),
    list(c(18,4), c(8,9), c(11,15), c(13,5), c(2,16), c(1,7), c(14,12), c(17,3), c(10,6)),
    list(c(2,6), c(16,12), c(4,8), c(1,3), c(10,18), c(15,14), c(7,13), c(11,5), c(17,9)),
    list(c(3,12), c(5,14), c(7,16), c(18,9), c(11,2), c(4,13), c(15,6), c(8,17), c(1,10)),
    list(c(11,16), c(18,13), c(15,2), c(4,17), c(6,1), c(8,3), c(5,10), c(12,7), c(9,14))
  )
  
  # Generate fixtures for rounds 1-17
  for (round_num in 1:17) {
    round_matches <- schedule[[round_num]]
    for (match in round_matches) {
      fixtures <- rbind(fixtures, data.frame(
        home = team_names[match[1]],
        away = team_names[match[2]],
        date = start_date + (round_num - 1) * 7,
        stringsAsFactors = FALSE
      ))
    }
  }
  
  # Generate reverse fixtures for rounds 18-34
  first_round_fixtures <- fixtures
  for (round_num in 18:34) {
    # Get corresponding matches from first round
    original_round <- round_num - 17
    start_idx <- (original_round - 1) * 9 + 1
    end_idx <- original_round * 9
    
    for (i in start_idx:end_idx) {
      fixtures <- rbind(fixtures, data.frame(
        home = first_round_fixtures$away[i],
        away = first_round_fixtures$home[i],
        date = start_date + (round_num - 1) * 7,
        stringsAsFactors = FALSE
      ))
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
  
  # Generate realistic ELO distribution based on n_teams
  if (n_teams >= 18) {
    # Standard distribution for 18 or more teams
    n_top <- ceiling(n_teams * 0.17)     # ~17% top teams
    n_upper <- ceiling(n_teams * 0.33)   # ~33% upper mid
    n_lower <- ceiling(n_teams * 0.33)   # ~33% lower mid
    n_bottom <- n_teams - n_top - n_upper - n_lower  # Rest are bottom
    
    elos <- c(
      runif(n_top, 1700, 1800),      # Top teams
      runif(n_upper, 1500, 1650),    # Upper mid-table
      runif(n_lower, 1350, 1500),    # Lower mid-table
      runif(n_bottom, 1200, 1350)    # Bottom teams
    )
  } else {
    # For smaller leagues, distribute evenly across the range
    elos <- seq(1200, 1800, length.out = n_teams)
    # Add some randomness
    elos <- elos + runif(n_teams, -50, 50)
  }
  
  # Ensure average is exactly 1500
  elos <- elos - mean(elos) + 1500
  
  return(data.frame(
    Team = team_names,
    ELO = round(elos),
    stringsAsFactors = FALSE
  ))
}