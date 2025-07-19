# ELO Aggregation Functions
# Calculates final ELO ratings and Liga3 relegation baselines

calculate_final_elos <- function(season) {
  # Aggregate final ELO ratings from all matches in a season
  # Returns data frame with TeamID and FinalELO
  
  tryCatch({
    # Load team list for the season - check for temporary files first
    team_list_file <- paste0("RCode/TeamList_", season, ".csv")
    
    # Check if we have temporary files from current processing
    temp_files <- list.files("RCode", pattern = paste0("TeamList_", season, "_League.*_temp\\.csv$"), full.names = TRUE)
    
    if (length(temp_files) > 0) {
      # We have temporary files, merge them to get the team list
      cat("Using temporary files for ELO calculation in season", season, "\n")
      
      team_list <- data.frame()
      for (file in temp_files) {
        if (file.exists(file)) {
          league_data <- read.csv(file, sep = ";", stringsAsFactors = FALSE)
          if (!is.null(league_data) && nrow(league_data) > 0) {
            team_list <- rbind(team_list, league_data)
          }
        }
      }
      
      if (nrow(team_list) == 0) {
        stop(paste("No valid team data found in temporary files for season", season))
      }
    } else if (file.exists(team_list_file)) {
      # Use regular team list file
      team_list <- read.csv(team_list_file, sep = ";", stringsAsFactors = FALSE)
    } else {
      stop(paste("Team list file not found:", team_list_file))
    }
    
    # Initialize ELO tracking
    current_elos <- data.frame(
      TeamID = team_list$TeamID,
      CurrentELO = team_list$InitialELO,
      stringsAsFactors = FALSE
    )
    
    # Process all leagues
    leagues <- c("78", "79", "80")  # Bundesliga, 2. Bundesliga, 3. Liga
    
    for (league in leagues) {
      cat("Processing ELO updates for league", league, "season", season, "\n")
      
      # Get match results for this league
      matches <- get_league_matches(league, season)
      
      if (is.null(matches) || nrow(matches) == 0) {
        cat("No matches found for league", league, "season", season, "- ELO values will remain unchanged\n")
        next
      }
      
      cat("Processing", nrow(matches), "matches for league", league, "season", season, "\n")
      
      # Process each match chronologically
      matches_sorted <- matches[order(matches$fixture_date), ]
      
      for (i in 1:nrow(matches_sorted)) {
        match <- matches_sorted[i, ]
        
        # Update ELOs based on match result
        current_elos <- update_elos_for_match(current_elos, match)
      }
    }
    
    # Return final ELOs
    final_elos <- data.frame(
      TeamID = current_elos$TeamID,
      FinalELO = current_elos$CurrentELO,
      stringsAsFactors = FALSE
    )
    
    # Debug: Show ELO changes
    initial_sum <- sum(team_list$InitialELO)
    final_sum <- sum(final_elos$FinalELO)
    cat("ELO Summary - Initial total:", initial_sum, "Final total:", final_sum, "\n")
    
    # Show some specific changes for key teams
    key_teams <- c(168, 1320, 4259)  # B04, Cottbus, Aachen
    for (team_id in key_teams) {
      initial_idx <- which(team_list$TeamID == team_id)
      final_idx <- which(final_elos$TeamID == team_id)
      if (length(initial_idx) > 0 && length(final_idx) > 0) {
        initial_elo <- team_list$InitialELO[initial_idx[1]]
        final_elo <- final_elos$FinalELO[final_idx[1]]
        cat("Team", team_id, "ELO change:", initial_elo, "->", final_elo, "(", final_elo - initial_elo, ")\n")
      }
    }
    
    return(final_elos)
    
  }, error = function(e) {
    stop(paste("Error calculating final ELOs for season", season, ":", e$message))
  })
}

get_league_matches <- function(league, season) {
  # Get all finished matches for a league and season
  # Returns data frame with match information
  
  tryCatch({
    # Always use fetch_league_results for ELO calculations
    # retrieveResults doesn't return the required data structure
    results <- fetch_league_results(league, season)
    
    if (is.null(results)) {
      return(NULL)
    }
    
    # Filter for finished matches only
    finished_matches <- results[results$fixture_status_short == "FT", ]
    
    # Extract required columns
    match_data <- data.frame(
      fixture_date = finished_matches$fixture_date,
      teams_home_id = finished_matches$teams_home_id,
      teams_away_id = finished_matches$teams_away_id,
      goals_home = finished_matches$goals_home,
      goals_away = finished_matches$goals_away,
      stringsAsFactors = FALSE
    )
    
    return(match_data)
    
  }, error = function(e) {
    warning(paste("Error fetching matches for league", league, "season", season, ":", e$message))
    return(NULL)
  })
}

fetch_league_results <- function(league, season) {
  # Direct API call fallback for league results
  # Returns raw API response data
  
  api_key <- Sys.getenv("RAPIDAPI_KEY")
  if (api_key == "") {
    stop("RAPIDAPI_KEY environment variable not set")
  }
  
  url <- "https://api-football-v1.p.rapidapi.com/v3/fixtures"
  
  query_params <- list(
    league = league,
    season = season,
    status = "FT"
  )
  
  response <- httr::GET(
    url,
    query = query_params,
    httr::add_headers(
      'X-RapidAPI-Key' = api_key,
      'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
    )
  )
  
  if (httr::status_code(response) != 200) {
    stop(paste("API call failed with status", httr::status_code(response)))
  }
  
  content <- httr::content(response, "text", encoding = "UTF-8")
  data <- jsonlite::fromJSON(content)
  
  if (is.null(data$response)) {
    return(NULL)
  }
  
  # Transform API response to expected format
  fixtures <- data$response
  
  # Extract match data
  match_data <- data.frame(
    fixture_date = fixtures$fixture$date,
    teams_home_id = fixtures$teams$home$id,
    teams_away_id = fixtures$teams$away$id,
    goals_home = fixtures$goals$home,
    goals_away = fixtures$goals$away,
    fixture_status_short = fixtures$fixture$status$short,
    stringsAsFactors = FALSE
  )
  
  return(match_data)
}

update_elos_for_match <- function(current_elos, match) {
  # Update ELO ratings based on a single match result
  # Uses the existing SpielNichtSimulieren function if available
  
  home_team_id <- match$teams_home_id
  away_team_id <- match$teams_away_id
  goals_home <- match$goals_home
  goals_away <- match$goals_away
  
  # Get current ELOs
  home_elo <- current_elos$CurrentELO[current_elos$TeamID == home_team_id]
  away_elo <- current_elos$CurrentELO[current_elos$TeamID == away_team_id]
  
  if (length(home_elo) == 0 || length(away_elo) == 0) {
    warning(paste("Team not found in ELO data for match:", home_team_id, "vs", away_team_id))
    return(current_elos)
  }
  
  # Use existing ELO calculation if available
  if (exists("SpielNichtSimulieren")) {
    # Use standard parameters
    mod_factor <- 20  # Standard K-factor
    home_advantage <- 100  # Standard home advantage
    
    # Calculate new ELOs
    elo_result <- SpielNichtSimulieren(
      home_elo[1], away_elo[1], 
      goals_home, goals_away, 
      mod_factor, home_advantage
    )
    
    # Update current ELOs
    current_elos$CurrentELO[current_elos$TeamID == home_team_id] <- elo_result[1]
    current_elos$CurrentELO[current_elos$TeamID == away_team_id] <- elo_result[2]
    
  } else {
    # Fallback ELO calculation
    new_elos <- calculate_elo_update(home_elo[1], away_elo[1], goals_home, goals_away)
    
    current_elos$CurrentELO[current_elos$TeamID == home_team_id] <- new_elos$home_elo
    current_elos$CurrentELO[current_elos$TeamID == away_team_id] <- new_elos$away_elo
  }
  
  return(current_elos)
}

calculate_elo_update <- function(home_elo, away_elo, goals_home, goals_away) {
  # Fallback ELO calculation function
  # Implements standard ELO with goal difference modifier
  
  # Standard parameters
  k_factor <- 20
  home_advantage <- 100
  
  # Calculate expected probability
  elo_diff <- (away_elo - home_elo - home_advantage)
  elo_diff <- max(min(elo_diff, 400), -400)  # Clamp to ±400
  
  expected_prob <- 1 / (1 + 10^(elo_diff / 400))
  
  # Calculate actual result
  goal_diff <- goals_home - goals_away
  actual_result <- (sign(goal_diff) + 1) / 2  # 0 for loss, 0.5 for draw, 1 for win
  
  # Goal difference modifier
  goal_modifier <- sqrt(max(abs(goal_diff), 1))
  
  # Calculate ELO change
  elo_change <- (actual_result - expected_prob) * goal_modifier * k_factor
  
  return(list(
    home_elo = home_elo + elo_change,
    away_elo = away_elo - elo_change
  ))
}

calculate_liga3_relegation_baseline <- function(season) {
  # Calculate mean ELO of last 4 Liga3 teams for relegation baseline
  # Returns baseline ELO value
  
  tryCatch({
    # Get final ELOs for all teams
    final_elos <- calculate_final_elos(season)
    
    # Get Liga3 teams (league 80)
    liga3_matches <- get_league_matches("80", season)
    
    if (is.null(liga3_matches) || nrow(liga3_matches) == 0) {
      warning(paste("No Liga3 matches found for season", season))
      return(1046)  # Default fallback ELO
    }
    
    # Get all Liga3 team IDs
    liga3_teams <- unique(c(liga3_matches$teams_home_id, liga3_matches$teams_away_id))
    
    # Filter final ELOs for Liga3 teams
    liga3_elos <- final_elos[final_elos$TeamID %in% liga3_teams, ]
    
    if (nrow(liga3_elos) < 4) {
      warning(paste("Not enough Liga3 teams found for baseline calculation (", nrow(liga3_elos), "teams)"))
      return(1046)  # Default fallback ELO
    }
    
    # Sort by ELO and take bottom 4
    liga3_elos_sorted <- liga3_elos[order(liga3_elos$FinalELO), ]
    bottom_4_elos <- liga3_elos_sorted$FinalELO[1:4]
    
    # Calculate mean
    baseline <- mean(bottom_4_elos)
    
    cat("Liga3 relegation baseline for season", season, ":", round(baseline, 2), "\n")
    cat("Based on teams:", liga3_elos_sorted$TeamID[1:4], "with ELOs:", round(bottom_4_elos, 2), "\n")
    
    return(baseline)
    
  }, error = function(e) {
    warning(paste("Error calculating Liga3 baseline for season", season, ":", e$message))
    return(1046)  # Default fallback ELO
  })
}

get_initial_elo_for_new_team <- function(league, baseline = NULL) {
  # Determine initial ELO for new/promoted teams
  # Uses baseline for Liga3, default values for others
  
  if (league == "80" && !is.null(baseline)) {
    # Use Liga3 relegation baseline
    return(baseline)
  } else if (league == "80") {
    # Default Liga3 ELO
    return(1046)
  } else if (league == "79") {
    # Default 2. Bundesliga ELO
    return(1350)
  } else if (league == "78") {
    # Default Bundesliga ELO
    return(1500)
  } else {
    # Fallback default
    return(1200)
  }
}

validate_elo_calculations <- function(season) {
  # Validate ELO calculations for consistency
  # Returns validation results
  
  tryCatch({
    final_elos <- calculate_final_elos(season)
    
    validation_results <- list(
      total_teams = nrow(final_elos),
      min_elo = min(final_elos$FinalELO),
      max_elo = max(final_elos$FinalELO),
      mean_elo = mean(final_elos$FinalELO),
      teams_with_valid_elos = sum(final_elos$FinalELO > 0),
      teams_with_extreme_elos = sum(final_elos$FinalELO < 800 | final_elos$FinalELO > 2200)
    )
    
    # Log validation results
    cat("ELO Validation Results for Season", season, ":\n")
    cat("Total Teams:", validation_results$total_teams, "\n")
    cat("ELO Range:", round(validation_results$min_elo, 2), "-", round(validation_results$max_elo, 2), "\n")
    cat("Mean ELO:", round(validation_results$mean_elo, 2), "\n")
    cat("Teams with Extreme ELOs:", validation_results$teams_with_extreme_elos, "\n")
    
    return(validation_results)
    
  }, error = function(e) {
    warning(paste("Error validating ELO calculations for season", season, ":", e$message))
    return(NULL)
  })
}

export_elo_progression <- function(season, output_file = NULL) {
  # Export ELO progression data for analysis
  # Useful for debugging and verification
  
  if (is.null(output_file)) {
    output_file <- paste0("elo_progression_", season, ".csv")
  }
  
  tryCatch({
    final_elos <- calculate_final_elos(season)
    
    # Add initial ELOs for comparison
    team_list_file <- paste0("RCode/TeamList_", season, ".csv")
    if (file.exists(team_list_file)) {
      initial_elos <- read.csv(team_list_file, sep = ";", stringsAsFactors = FALSE)
      
      # Merge initial and final ELOs
      elo_progression <- merge(
        initial_elos[, c("TeamID", "InitialELO")],
        final_elos,
        by = "TeamID"
      )
      
      # Calculate ELO change
      elo_progression$ELO_Change <- elo_progression$FinalELO - elo_progression$InitialELO
      
      # Write to CSV
      write.csv(elo_progression, output_file, row.names = FALSE)
      
      cat("ELO progression exported to:", output_file, "\n")
      
      return(elo_progression)
    }
    
  }, error = function(e) {
    warning(paste("Error exporting ELO progression for season", season, ":", e$message))
    return(NULL)
  })
}