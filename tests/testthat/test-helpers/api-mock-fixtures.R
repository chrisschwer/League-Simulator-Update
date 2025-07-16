# API Mock Fixtures for Integration Tests
# This file provides mock API responses and utilities for testing API integration

#' Create mock fixture data structure
#' 
#' @param league_id League ID (963 = Bundesliga, 964 = 2. Bundesliga, 965 = 3. Liga)
#' @param season Season year
#' @param status Match status (finished, scheduled, in_play)
#' @return Data frame matching API response structure
create_mock_fixtures <- function(league_id = 963, season = 2024, status = "finished") {
  teams <- get_league_teams(league_id)
  n_teams <- length(teams)
  
  fixtures <- data.frame(
    fixture_id = integer(),
    home_team = character(),
    away_team = character(),
    home_score = integer(),
    away_score = integer(),
    status = character(),
    date = character(),
    league = integer(),
    season = integer(),
    stringsAsFactors = FALSE
  )
  
  fixture_id <- 1000000 + league_id * 1000
  
  # Generate fixtures based on status
  if (status == "finished") {
    # Use ELO-based generator for realistic results
    test_teams <- data.frame(
      Team = teams,
      ELO = round(rnorm(n_teams, 1500, 150))
    )
    
    season_fixtures <- generate_season_fixtures(teams)
    elo_results <- generate_elo_based_results(test_teams, season_fixtures[1:90,], seed = league_id)
    
    for (i in 1:length(elo_results$results)) {
      result <- elo_results$results[[i]]
      fixtures <- rbind(fixtures, data.frame(
        fixture_id = fixture_id + i,
        home_team = result$home,
        away_team = result$away,
        home_score = result$home_goals,
        away_score = result$away_goals,
        status = "finished",
        date = format(result$match_date, "%Y-%m-%d"),
        league = league_id,
        season = season,
        stringsAsFactors = FALSE
      ))
    }
  } else {
    # Generate scheduled fixtures
    for (i in 1:(n_teams - 1)) {
      for (j in (i + 1):n_teams) {
        fixture_id <- fixture_id + 1
        fixtures <- rbind(fixtures, data.frame(
          fixture_id = fixture_id,
          home_team = teams[i],
          away_team = teams[j],
          home_score = NA,
          away_score = NA,
          status = "scheduled",
          date = format(Sys.Date() + 7 * (fixture_id %% 34), "%Y-%m-%d"),
          league = league_id,
          season = season,
          stringsAsFactors = FALSE
        ))
      }
    }
  }
  
  return(fixtures)
}

#' Get teams for a specific league
#' 
#' @param league_id League identifier
#' @return Vector of team names
get_league_teams <- function(league_id) {
  if (league_id == 963) {
    # Bundesliga teams
    return(c(
      "Bayern Munich", "Borussia Dortmund", "RB Leipzig", "Bayer Leverkusen",
      "Eintracht Frankfurt", "Union Berlin", "SC Freiburg", "VfL Wolfsburg",
      "1. FSV Mainz 05", "Borussia Moenchengladbach", "FC Koeln", "TSG Hoffenheim",
      "SV Werder Bremen", "VfL Bochum", "FC Augsburg", "VfB Stuttgart",
      "1. FC Heidenheim", "SV Darmstadt 98"
    ))
  } else if (league_id == 964) {
    # 2. Bundesliga teams
    return(paste0("2BL_Team", sprintf("%02d", 1:18)))
  } else if (league_id == 965) {
    # 3. Liga teams
    return(paste0("3L_Team", sprintf("%02d", 1:20)))
  }
}

#' Create mock API error response
#' 
#' @param status_code HTTP status code
#' @param message Error message
#' @return List representing error response
create_mock_error <- function(status_code, message = NULL) {
  if (is.null(message)) {
    message <- switch(as.character(status_code),
      "429" = "Too Many Requests",
      "500" = "Internal Server Error",
      "503" = "Service Unavailable",
      "404" = "Not Found",
      "Unknown Error"
    )
  }
  
  return(list(
    status_code = status_code,
    error = TRUE,
    message = message
  ))
}

#' Mock API response wrapper
#' 
#' @param data Response data or error
#' @param delay Simulated response delay in seconds
#' @return API response structure
mock_api_response <- function(data, delay = 0) {
  if (delay > 0) {
    Sys.sleep(delay)
  }
  
  if (is.list(data) && !is.null(data$error)) {
    # Error response
    return(data)
  }
  
  # Success response
  return(list(
    status_code = 200,
    data = data,
    headers = list(
      "x-ratelimit-limit" = "100",
      "x-ratelimit-remaining" = "99",
      "x-ratelimit-reset" = as.character(Sys.time() + 3600)
    )
  ))
}

#' Create mock team standings
#' 
#' @param league_id League identifier
#' @param matchday Current matchday
#' @return Data frame with league standings
create_mock_standings <- function(league_id = 963, matchday = 10) {
  teams <- get_league_teams(league_id)
  n_teams <- length(teams)
  
  # Generate realistic points distribution
  max_points <- matchday * 3
  points <- sort(round(runif(n_teams, 0, max_points * 0.8)), decreasing = TRUE)
  
  standings <- data.frame(
    position = 1:n_teams,
    team = teams,
    played = matchday,
    won = round(points / 3),
    draw = round((matchday - points / 3) / 2),
    lost = matchday - round(points / 3) - round((matchday - points / 3) / 2),
    points = points,
    goals_for = round(runif(n_teams, matchday * 0.5, matchday * 2.5)),
    goals_against = round(runif(n_teams, matchday * 0.5, matchday * 2)),
    stringsAsFactors = FALSE
  )
  
  standings$goal_diff <- standings$goals_for - standings$goals_against
  
  return(standings)
}

#' Simulate API rate limiting
#' 
#' @param call_count Number of calls made
#' @param limit Rate limit threshold
#' @return TRUE if rate limited, FALSE otherwise
simulate_rate_limit <- function(call_count, limit = 10) {
  return(call_count >= limit)
}

#' Create mock HTTP test context
#' 
#' @param responses List of responses to return in sequence
#' @return Function that returns next response
create_mock_http_sequence <- function(responses) {
  call_count <- 0
  
  function() {
    call_count <<- call_count + 1
    if (call_count <= length(responses)) {
      return(responses[[call_count]])
    }
    # Default to success after sequence
    return(mock_api_response(create_mock_fixtures()))
  }
}

#' Load mock fixture from file
#' 
#' @param filename Fixture filename
#' @return Fixture data
load_mock_fixture <- function(filename) {
  fixture_path <- file.path("tests", "testthat", "fixtures", "api-responses", filename)
  if (file.exists(fixture_path)) {
    return(readRDS(fixture_path))
  }
  stop(paste("Fixture not found:", filename))
}

#' Save mock fixture to file
#' 
#' @param data Data to save
#' @param filename Fixture filename
save_mock_fixture <- function(data, filename) {
  fixture_path <- file.path("tests", "testthat", "fixtures", "api-responses", filename)
  dir.create(dirname(fixture_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(data, fixture_path)
}