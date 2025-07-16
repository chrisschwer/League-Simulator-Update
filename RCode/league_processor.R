# League-Specific Processing
# Handles league-specific business logic and rules

process_bundesliga <- function(season, teams, final_elos) {
  # Process Bundesliga (league 78)
  # Standard processing without special cases
  
  tryCatch({
    cat("Processing Bundesliga teams for season", season, "\n")
    
    processed_teams <- list()
    
    for (i in seq_along(teams)) {
      team <- teams[[i]]
      
      # Get ELO from previous season
      team_elo <- final_elos$FinalELO[final_elos$TeamID == team$id]
      
      if (length(team_elo) == 0) {
        # New team (promoted from 2. Bundesliga)
        initial_elo <- get_initial_elo_for_new_team("78")
        
        cat("New Bundesliga team:", team$name, "- Initial ELO:", initial_elo, "\n")
        
        # Prompt for team information
        team_info <- prompt_for_team_info(team$name, "78")
        
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = team_info$short_name,
          initial_elo = team_info$initial_elo,
          promotion_value = 0  # Bundesliga teams don't have promotion restrictions
        )
      } else {
        # Existing team
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = get_team_short_name(team$name),
          initial_elo = team_elo[1],
          promotion_value = 0
        )
      }
      
      processed_teams[[i]] <- processed_team
    }
    
    return(processed_teams)
    
  }, error = function(e) {
    warning("Error processing Bundesliga teams:", e$message)
    return(NULL)
  })
}

process_segunda_bundesliga <- function(season, teams, final_elos) {
  # Process 2. Bundesliga (league 79)
  # Standard processing without special cases
  
  tryCatch({
    cat("Processing 2. Bundesliga teams for season", season, "\n")
    
    processed_teams <- list()
    
    for (i in seq_along(teams)) {
      team <- teams[[i]]
      
      # Get ELO from previous season
      team_elo <- final_elos$FinalELO[final_elos$TeamID == team$id]
      
      if (length(team_elo) == 0) {
        # New team (promoted from 3. Liga or relegated from Bundesliga)
        initial_elo <- get_initial_elo_for_new_team("79")
        
        cat("New 2. Bundesliga team:", team$name, "- Initial ELO:", initial_elo, "\n")
        
        # Prompt for team information
        team_info <- prompt_for_team_info(team$name, "79")
        
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = team_info$short_name,
          initial_elo = team_info$initial_elo,
          promotion_value = 0  # 2. Bundesliga teams don't have promotion restrictions
        )
      } else {
        # Existing team
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = get_team_short_name(team$name),
          initial_elo = team_elo[1],
          promotion_value = 0
        )
      }
      
      processed_teams[[i]] <- processed_team
    }
    
    return(processed_teams)
    
  }, error = function(e) {
    warning("Error processing 2. Bundesliga teams:", e$message)
    return(NULL)
  })
}

process_liga3 <- function(season, teams, final_elos, relegation_baseline) {
  # Process 3. Liga (league 80)
  # Handles second teams and relegation baseline
  
  tryCatch({
    cat("Processing 3. Liga teams for season", season, "\n")
    cat("Liga3 relegation baseline:", round(relegation_baseline, 2), "\n")
    
    processed_teams <- list()
    
    for (i in seq_along(teams)) {
      team <- teams[[i]]
      
      # Detect second teams
      is_second_team <- detect_second_teams(team$name)
      
      # Get ELO from previous season
      team_elo <- final_elos$FinalELO[final_elos$TeamID == team$id]
      
      if (length(team_elo) == 0) {
        # New team
        if (is_second_team) {
          # Second team - use relegation baseline
          initial_elo <- relegation_baseline
          promotion_value <- -50
          
          cat("New Liga3 second team:", team$name, "- ELO:", round(initial_elo, 2), "\n")
        } else {
          # Regular team - use standard initial ELO
          initial_elo <- get_initial_elo_for_new_team("80", relegation_baseline)
          promotion_value <- 0
          
          cat("New Liga3 team:", team$name, "- ELO:", round(initial_elo, 2), "\n")
        }
        
        # Prompt for team information
        team_info <- prompt_for_team_info(team$name, "80")
        
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = team_info$short_name,
          initial_elo = team_info$initial_elo,
          promotion_value = promotion_value,
          is_second_team = is_second_team
        )
      } else {
        # Existing team
        promotion_value <- ifelse(is_second_team, -50, 0)
        
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = get_team_short_name(team$name),
          initial_elo = team_elo[1],
          promotion_value = promotion_value,
          is_second_team = is_second_team
        )
      }
      
      processed_teams[[i]] <- processed_team
    }
    
    return(processed_teams)
    
  }, error = function(e) {
    warning("Error processing 3. Liga teams:", e$message)
    return(NULL)
  })
}

validate_league_composition <- function(league_id, teams) {
  # Validate league composition and team count
  # Returns validation results
  
  tryCatch({
    league_name <- get_league_name(league_id)
    
    # Expected team counts
    expected_counts <- list(
      "78" = 18,  # Bundesliga
      "79" = 18,  # 2. Bundesliga
      "80" = 20   # 3. Liga
    )
    
    expected_count <- expected_counts[[league_id]]
    actual_count <- length(teams)
    
    if (is.null(expected_count)) {
      return(list(
        valid = FALSE,
        message = paste("Unknown league:", league_id)
      ))
    }
    
    # Allow some variance (±2 teams)
    if (abs(actual_count - expected_count) > 2) {
      return(list(
        valid = FALSE,
        message = paste(
          "Unexpected team count for", league_name,
          "- Expected:", expected_count,
          "Actual:", actual_count
        )
      ))
    }
    
    # Liga3 specific validation
    if (league_id == "80") {
      second_teams <- sum(sapply(teams, function(t) t$is_second_team %||% FALSE))
      
      if (second_teams > 4) {
        return(list(
          valid = FALSE,
          message = paste("Too many second teams in Liga3:", second_teams)
        ))
      }
    }
    
    return(list(
      valid = TRUE,
      message = paste("League composition valid for", league_name),
      expected_count = expected_count,
      actual_count = actual_count
    ))
    
  }, error = function(e) {
    return(list(
      valid = FALSE,
      message = paste("Validation error:", e$message)
    ))
  })
}

get_league_promotion_rules <- function(league_id) {
  # Get promotion/relegation rules for league
  # Returns rules structure
  
  rules <- list(
    "78" = list(
      name = "Bundesliga",
      promotion_to = NULL,
      promotion_slots = 0,
      relegation_to = "79",
      relegation_slots = 2,
      playoff_slots = 1,
      restrictions = "None"
    ),
    "79" = list(
      name = "2. Bundesliga",
      promotion_to = "78",
      promotion_slots = 2,
      relegation_to = "80",
      relegation_slots = 2,
      playoff_slots = 1,
      restrictions = "None"
    ),
    "80" = list(
      name = "3. Liga",
      promotion_to = "79",
      promotion_slots = 2,
      relegation_to = "Regional",
      relegation_slots = 4,
      playoff_slots = 1,
      restrictions = "Second teams cannot be promoted"
    )
  )
  
  return(rules[[league_id]])
}

calculate_league_elo_distribution <- function(teams) {
  # Calculate ELO distribution statistics for league
  # Returns distribution data
  
  tryCatch({
    elos <- sapply(teams, function(t) t$initial_elo)
    
    distribution <- list(
      min = min(elos),
      max = max(elos),
      mean = mean(elos),
      median = median(elos),
      sd = sd(elos),
      q25 = quantile(elos, 0.25),
      q75 = quantile(elos, 0.75),
      teams = length(elos)
    )
    
    return(distribution)
    
  }, error = function(e) {
    warning("Error calculating ELO distribution:", e$message)
    return(NULL)
  })
}

generate_league_report <- function(league_id, season, teams, distribution) {
  # Generate league processing report
  # Returns formatted report
  
  tryCatch({
    league_name <- get_league_name(league_id)
    rules <- get_league_promotion_rules(league_id)
    
    report <- list(
      league_id = league_id,
      league_name = league_name,
      season = season,
      team_count = length(teams),
      expected_count = rules$promotion_slots + rules$relegation_slots,
      elo_distribution = distribution,
      promotion_rules = rules,
      timestamp = Sys.time()
    )
    
    # Add Liga3 specific information
    if (league_id == "80") {
      second_teams <- sum(sapply(teams, function(t) t$is_second_team %||% FALSE))
      report$second_teams = second_teams
    }
    
    # Print summary
    cat("\n--- League Report:", league_name, "---\n")
    cat("Season:", season, "\n")
    cat("Teams:", length(teams), "\n")
    
    if (!is.null(distribution)) {
      cat("ELO Range:", round(distribution$min, 2), "-", round(distribution$max, 2), "\n")
      cat("Mean ELO:", round(distribution$mean, 2), "\n")
    }
    
    if (league_id == "80") {
      cat("Second Teams:", report$second_teams, "\n")
    }
    
    cat("---", rep("-", nchar(league_name) + 16), "\n")
    
    return(report)
    
  }, error = function(e) {
    warning("Error generating league report:", e$message)
    return(NULL)
  })
}

apply_league_specific_rules <- function(league_id, teams) {
  # Apply league-specific business rules
  # Returns modified teams list
  
  tryCatch({
    if (league_id == "80") {
      # Liga3 specific rules
      for (i in seq_along(teams)) {
        team <- teams[[i]]
        
        # Mark second teams
        if (detect_second_teams(team$name)) {
          team$is_second_team <- TRUE
          team$promotion_value <- -50
        } else {
          team$is_second_team <- FALSE
          team$promotion_value <- 0
        }
        
        teams[[i]] <- team
      }
    } else {
      # Bundesliga and 2. Bundesliga
      for (i in seq_along(teams)) {
        team <- teams[[i]]
        team$is_second_team <- FALSE
        team$promotion_value <- 0
        teams[[i]] <- team
      }
    }
    
    return(teams)
    
  }, error = function(e) {
    warning("Error applying league rules:", e$message)
    return(teams)
  })
}

validate_team_eligibility <- function(team, league_id) {
  # Validate team eligibility for league
  # Returns eligibility status
  
  tryCatch({
    eligibility <- list(
      eligible = TRUE,
      reasons = c()
    )
    
    # Liga3 specific eligibility
    if (league_id == "80") {
      # Check if second team's parent is in higher league
      if (team$is_second_team %||% FALSE) {
        # This would require checking parent team league
        # For now, we'll assume second teams are eligible
        eligibility$reasons <- c(eligibility$reasons, "Second team - promotion restricted")
      }
    }
    
    # General eligibility checks
    if (is.null(team$name) || nchar(team$name) < 2) {
      eligibility$eligible <- FALSE
      eligibility$reasons <- c(eligibility$reasons, "Invalid team name")
    }
    
    if (is.null(team$id) || !is.numeric(team$id)) {
      eligibility$eligible <- FALSE
      eligibility$reasons <- c(eligibility$reasons, "Invalid team ID")
    }
    
    return(eligibility)
    
  }, error = function(e) {
    return(list(
      eligible = FALSE,
      reasons = paste("Validation error:", e$message)
    ))
  })
}

sort_teams_by_league_position <- function(teams, league_id) {
  # Sort teams by expected league position
  # Uses ELO as proxy for strength
  
  tryCatch({
    # Sort by ELO (descending)
    sorted_teams <- teams[order(sapply(teams, function(t) t$initial_elo), decreasing = TRUE)]
    
    # Liga3 specific sorting - second teams at bottom
    if (league_id == "80") {
      regular_teams <- sorted_teams[!sapply(sorted_teams, function(t) t$is_second_team %||% FALSE)]
      second_teams <- sorted_teams[sapply(sorted_teams, function(t) t$is_second_team %||% FALSE)]
      
      sorted_teams <- c(regular_teams, second_teams)
    }
    
    return(sorted_teams)
    
  }, error = function(e) {
    warning("Error sorting teams:", e$message)
    return(teams)
  })
}