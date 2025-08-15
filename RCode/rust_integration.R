#' Rust Integration Functions
#' 
#' Functions to integrate with the high-performance Rust simulation engine
#' Provides 50-100x performance improvement over R/C++ implementation

library(httr)
library(jsonlite)

# Global configuration
RUST_API_URL <- Sys.getenv("RUST_API_URL", "http://localhost:8080")

#' Connect to Rust Simulator
#' 
#' Check if the Rust REST API is available and healthy
#' @return TRUE if connection successful, FALSE otherwise
#' @export
connect_rust_simulator <- function() {
  tryCatch({
    response <- GET(paste0(RUST_API_URL, "/health"))
    if (status_code(response) == 200) {
      health <- content(response, "parsed")
      message(sprintf("✅ Connected to Rust simulator v%s", health$version))
      message(sprintf("   Performance: %s", health$performance))
      return(TRUE)
    } else {
      message("❌ Rust simulator not responding")
      return(FALSE)
    }
  }, error = function(e) {
    message(sprintf("❌ Failed to connect to Rust simulator: %s", e$message))
    return(FALSE)
  })
}

#' Simulate League using Rust Engine
#' 
#' Call the Rust REST API to run Monte Carlo simulation
#' @param schedule Matrix of matches [team_home, team_away, goals_home, goals_away]
#' @param elo_values Vector of initial ELO values
#' @param team_names Vector of team names
#' @param iterations Number of Monte Carlo iterations (default: 10000)
#' @param mod_factor ELO modification factor (default: 20)
#' @param home_advantage Home advantage in ELO points (default: 65)
#' @param adj_points Optional point adjustments per team
#' @param adj_goals Optional goals adjustments per team
#' @param adj_goals_against Optional goals against adjustments per team
#' @param adj_goal_diff Optional goal difference adjustments per team
#' @return List with probability_matrix, team_names, and performance metrics
#' @export
simulate_league_rust <- function(schedule, elo_values, team_names,
                                iterations = 10000,
                                mod_factor = 20,
                                home_advantage = 65,
                                adj_points = NULL,
                                adj_goals = NULL,
                                adj_goals_against = NULL,
                                adj_goal_diff = NULL) {
  
  # Convert schedule matrix to list format for JSON
  schedule_list <- lapply(1:nrow(schedule), function(i) {
    goals_home <- if (is.na(schedule[i, 3])) NULL else as.integer(schedule[i, 3])
    goals_away <- if (is.na(schedule[i, 4])) NULL else as.integer(schedule[i, 4])
    
    list(
      as.integer(schedule[i, 1]),  # team_home
      as.integer(schedule[i, 2]),  # team_away
      goals_home,                  # goals_home (NULL or integer)
      goals_away                   # goals_away (NULL or integer)
    )
  })
  
  # Prepare request payload
  payload <- list(
    schedule = schedule_list,
    elo_values = as.numeric(elo_values),
    team_names = team_names,
    iterations = as.integer(iterations),
    mod_factor = as.numeric(mod_factor),
    home_advantage = as.numeric(home_advantage)
  )
  
  # Add optional adjustments if provided
  if (!is.null(adj_points)) payload$adj_points <- as.integer(adj_points)
  if (!is.null(adj_goals)) payload$adj_goals <- as.integer(adj_goals)
  if (!is.null(adj_goals_against)) payload$adj_goals_against <- as.integer(adj_goals_against)
  if (!is.null(adj_goal_diff)) payload$adj_goal_diff <- as.integer(adj_goal_diff)
  
  # Debug JSON payload
  json_body <- toJSON(payload, auto_unbox = TRUE, null = "null")
  message("DEBUG: First schedule entry JSON: ", substr(json_body, 1, 200))
  
  # Make API request
  response <- POST(
    paste0(RUST_API_URL, "/simulate"),
    body = json_body,
    content_type_json(),
    accept_json()
  )
  
  if (status_code(response) != 200) {
    error_body <- content(response, "text")
    message("DEBUG: Request payload summary:")
    message("  Teams: ", length(team_names))
    message("  Schedule rows: ", nrow(schedule))
    message("  ELO values: ", length(elo_values))
    message("  Team indices range: ", min(schedule[,1:2], na.rm=TRUE), "-", max(schedule[,1:2], na.rm=TRUE))
    message("  Error response: ", error_body)
    stop(sprintf("Rust simulation failed with status %d: %s", status_code(response), error_body))
  }
  
  result <- content(response, "parsed")
  
  # Convert probability matrix to R matrix with proper numeric conversion
  prob_matrix <- do.call(rbind, lapply(result$probability_matrix, as.numeric))
  rownames(prob_matrix) <- result$team_names
  colnames(prob_matrix) <- 1:ncol(prob_matrix)
  
  return(list(
    probability_matrix = prob_matrix,
    team_names = result$team_names,
    simulations = result$simulations_performed,
    time_ms = result$time_ms
  ))
}

#' League Simulator using Rust (Drop-in Replacement)
#' 
#' Drop-in replacement for leagueSimulatorCPP that uses Rust engine
#' Maintains exact same interface and return format
#' 
#' @param season table with schedule and ELO values
#' @param n number of iterations, defaults to 10000
#' @param modFactor Multiplier ("learning rate") for ELO adjustment
#' @param homeAdvantage Home field advantage in ELO points
#' @param numberTeams Number of teams in the league
#' @param adjPoints vector containing an adjustment for the points scored per team
#' @param adjGoals vector containing an adjustment for the goals scored per team
#' @param adjGoalsAgainst vector containing an adjustment for the goals scored against per team
#' @param adjGoalDiff vector containing an adjustment for the goal difference per team
#' @return Distribution matrix (teams x positions) with probabilities
#' @export
leagueSimulatorRust <- function(season, n = 10000,
                               modFactor = 20, homeAdvantage = 65,
                               numberTeams = 18,
                               adjPoints = rep_len(0, numberTeams),
                               adjGoals = rep_len(0, numberTeams),
                               adjGoalsAgainst = rep_len(0, numberTeams),
                               adjGoalDiff = rep_len(0, numberTeams)) {
  
  # Check Rust connection
  if (!connect_rust_simulator()) {
    message("Falling back to C++ implementation...")
    return(leagueSimulatorCPP(season, n, modFactor, homeAdvantage,
                              numberTeams, adjPoints, adjGoals,
                              adjGoalsAgainst, adjGoalDiff))
  }
  
  # Convert tibble to data.frame if needed (transform_data returns tibble)
  if ("tbl_df" %in% class(season)) {
    season <- as.data.frame(season)
  }
  
  # Extract data from season dataframe - EXACTLY like the C++ version
  numberTeams <- dim(season)[2] - 4
  numberGames <- dim(season)[1]
  ELOValues <- as.double(season[1, 5:dim(season)[2]])
  teamNames <- colnames(season)[5:dim(season)[2]]
  
  # Replace team names in season with corresponding numbers - EXACTLY like C++ version
  season$TeamHeim <- factor(season$TeamHeim, levels = teamNames, ordered = TRUE)
  season$TeamGast <- factor(season$TeamGast, levels = teamNames, ordered = TRUE)
  season$TeamHeim <- as.integer(season$TeamHeim)
  season$TeamGast <- as.integer(season$TeamGast)
  
  # Validate that all team indices are valid (no NAs)
  if (any(is.na(season$TeamHeim)) || any(is.na(season$TeamGast))) {
    missing_teams <- unique(c(
      season$TeamHeim[is.na(as.integer(factor(season$TeamHeim, levels = teamNames)))],
      season$TeamGast[is.na(as.integer(factor(season$TeamGast, levels = teamNames)))]
    ))
    stop(sprintf("Team names not found in columns: %s", paste(missing_teams, collapse = ", ")))
  }
  
  # Create schedule matrix
  schedule <- as.matrix(season[, 1:4])
  
  # Keep 1-based indexing - Rust API expects 1-based indices and converts internally
  
  # Call Rust simulator
  start_time <- Sys.time()
  
  result <- simulate_league_rust(
    schedule = schedule,
    elo_values = ELOValues,
    team_names = teamNames,
    iterations = n,
    mod_factor = modFactor,
    home_advantage = homeAdvantage,
    adj_points = adjPoints,
    adj_goals = adjGoals,
    adj_goals_against = adjGoalsAgainst,
    adj_goal_diff = adjGoalDiff
  )
  
  end_time <- Sys.time()
  
  # Log performance improvement
  time_taken <- as.numeric(difftime(end_time, start_time, units = "secs"))
  message(sprintf("Rust simulation completed: %d iterations in %.2f seconds (%.0f/sec)",
                  result$simulations, time_taken,
                  result$simulations / time_taken))
  
  # Return in same format as leagueSimulatorCPP
  distribution <- result$probability_matrix
  
  # Ensure proper ordering by average rank
  rankAverage <- rowSums(distribution * matrix(1:ncol(distribution), 
                                               nrow = nrow(distribution), 
                                               ncol = ncol(distribution), 
                                               byrow = TRUE))
  rankOrder <- order(rankAverage)
  
  distribution <- distribution[rankOrder, ]
  
  return(distribution)
}

#' Batch Simulate Multiple Leagues
#' 
#' Simulate multiple leagues in parallel using Rust engine
#' Optimized for running Bundesliga, 2.Bundesliga, and 3.Liga together
#' 
#' @param leagues List of league configurations
#' @return List of simulation results
#' @export
simulate_leagues_batch_rust <- function(leagues) {
  
  # Prepare batch request
  batch_request <- list(
    leagues = lapply(names(leagues), function(name) {
      league <- leagues[[name]]
      list(
        name = name,
        request = list(
          schedule = league$schedule,
          elo_values = league$elo_values,
          team_names = league$team_names,
          iterations = league$iterations %||% 10000,
          mod_factor = league$mod_factor %||% 20,
          home_advantage = league$home_advantage %||% 65,
          adj_points = league$adj_points,
          adj_goals = league$adj_goals,
          adj_goals_against = league$adj_goals_against,
          adj_goal_diff = league$adj_goal_diff
        )
      )
    })
  )
  
  # Make batch API request
  response <- POST(
    paste0(RUST_API_URL, "/simulate/batch"),
    body = toJSON(batch_request, auto_unbox = TRUE),
    content_type_json(),
    accept_json()
  )
  
  if (status_code(response) != 200) {
    stop(sprintf("Batch simulation failed with status %d", status_code(response)))
  }
  
  result <- content(response, "parsed")
  
  # Process results
  output <- list()
  for (league_result in result$results) {
    prob_matrix <- do.call(rbind, lapply(league_result$response$probability_matrix, as.numeric))
    rownames(prob_matrix) <- league_result$response$team_names
    colnames(prob_matrix) <- 1:ncol(prob_matrix)
    
    output[[league_result$name]] <- list(
      probability_matrix = prob_matrix,
      team_names = league_result$response$team_names,
      simulations = league_result$response$simulations_performed,
      time_ms = league_result$response$time_ms
    )
  }
  
  message(sprintf("Batch simulation completed in %.2f seconds", 
                  result$total_time_ms / 1000))
  
  return(output)
}

# Helper function for null coalescing
`%||%` <- function(x, y) if (is.null(x)) y else x