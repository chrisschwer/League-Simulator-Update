# Season Processing Pipeline
# Main processing logic for season transitions

process_season_transition <- function(source_season, target_season) {
  # Main processing pipeline
  # Coordinates all phases of transition
  
  tryCatch({
    # Display welcome message
    display_welcome_message(source_season, target_season)
    
    # Validate inputs
    validate_season_range(source_season, target_season)
    
    # Check API access
    if (!validate_api_access()) {
      stop("API access validation failed")
    }
    
    # Get seasons to process
    seasons_to_process <- get_seasons_to_process(source_season, target_season)
    
    # Initialize tracking
    files_created <- c()
    seasons_processed <- 0
    
    # Process each season
    for (i in seq_along(seasons_to_process)) {
      season <- seasons_to_process[i]
      
      # Display progress
      display_progress(i, length(seasons_to_process))
      
      # Process single season
      season_result <- process_single_season(
        season, 
        ifelse(i == 1, source_season, seasons_to_process[i - 1])
      )
      
      if (season_result$success) {
        files_created <- c(files_created, season_result$files_created)
        seasons_processed <- seasons_processed + 1
        
        # Display season summary
        display_season_summary(season, season_result$teams_processed, season_result$files_created)
      } else {
        # Handle season processing error
        recovery_choice <- display_error_recovery_options(
          season_result$error, 
          paste("Season", season, "processing")
        )
        
        if (recovery_choice == "abort") {
          stop("Season processing aborted by user")
        } else if (recovery_choice == "retry") {
          # Retry current season
          i <- i - 1
          next
        } else if (recovery_choice == "skip") {
          # Skip current season and continue
          warning(paste("Skipping season", season, ":", season_result$error))
          next
        }
      }
    }
    
    # Display completion message
    display_completion_message(seasons_processed, files_created)
    
    return(list(
      success = TRUE,
      seasons_processed = seasons_processed,
      files_created = files_created
    ))
    
  }, error = function(e) {
    cat("Season transition failed:", e$message, "\n")
    return(list(
      success = FALSE,
      error = e$message
    ))
  })
}

process_single_season <- function(season, previous_season) {
  # Process transition for single season
  # Handles team discovery and ELO assignment
  
  tryCatch({
    cat("\n=== Processing Season", season, "===\n")
    
    # Get final ELOs from previous season
    cat("Calculating final ELOs for season", previous_season, "\n")
    final_elos <- calculate_final_elos(previous_season)
    
    # Calculate Liga3 relegation baseline
    cat("Calculating Liga3 relegation baseline\n")
    liga3_baseline <- calculate_liga3_relegation_baseline(previous_season)
    
    # Fetch teams for all leagues
    cat("Fetching team data from API\n")
    all_teams <- fetch_all_leagues_teams(season)
    
    if (is.null(all_teams) || length(all_teams) == 0) {
      return(list(
        success = FALSE,
        error = "No team data retrieved from API"
      ))
    }
    
    # Process each league
    files_created <- c()
    total_teams <- 0
    
    for (league_id in names(all_teams)) {
      league_teams <- all_teams[[league_id]]
      
      if (is.null(league_teams) || length(league_teams) == 0) {
        warning(paste("No teams for league", league_id))
        next
      }
      
      cat("Processing", get_league_name(league_id), "teams\n")
      
      # Process league teams
      processed_teams <- process_league_teams(
        league_teams, 
        league_id, 
        season, 
        final_elos,
        liga3_baseline
      )
      
      if (is.null(processed_teams)) {
        warning(paste("Failed to process league", league_id))
        next
      }
      
      # Generate CSV for this league's teams
      league_file <- generate_league_csv(processed_teams, league_id, season)
      
      if (!is.null(league_file)) {
        files_created <- c(files_created, league_file)
        total_teams <- total_teams + length(processed_teams)
      }
    }
    
    # Merge all leagues into single team list
    merged_file <- merge_league_files(files_created, season)
    
    if (!is.null(merged_file)) {
      files_created <- c(files_created, merged_file)
    }
    
    return(list(
      success = TRUE,
      teams_processed = total_teams,
      files_created = files_created
    ))
    
  }, error = function(e) {
    return(list(
      success = FALSE,
      error = e$message
    ))
  })
}

process_league_teams <- function(teams, league_id, season, final_elos, liga3_baseline) {
  # Process teams for a specific league
  # Handles ELO assignment and user prompts
  
  tryCatch({
    processed_teams <- list()
    existing_short_names <- c()
    
    for (i in seq_along(teams)) {
      team <- teams[[i]]
      
      # Check if team existed in previous season
      team_elo <- final_elos$FinalELO[final_elos$TeamID == team$id]
      
      if (length(team_elo) == 0) {
        # New team - need user input
        cat("\n--- New Team Detected ---\n")
        cat("Team ID:", team$id, "\n")
        cat("Team Name:", team$name, "\n")
        cat("League:", get_league_name(league_id), "\n")
        
        # Get team information interactively
        team_info <- prompt_for_team_info(team$name, league_id, existing_short_names)
        
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = team_info$short_name,
          initial_elo = team_info$initial_elo,
          promotion_value = team_info$promotion_value
        )
        
        existing_short_names <- c(existing_short_names, team_info$short_name)
        
      } else {
        # Existing team - use final ELO from previous season
        # Generate short name if not available
        short_name <- get_team_short_name(team$name)
        
        # Ensure uniqueness
        if (short_name %in% existing_short_names) {
          short_name <- generate_unique_short_name(short_name, existing_short_names)
        }
        
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = short_name,
          initial_elo = team_elo[1],
          promotion_value = ifelse(team$is_second_team, -50, 0)
        )
        
        existing_short_names <- c(existing_short_names, short_name)
      }
      
      processed_teams[[i]] <- processed_team
    }
    
    return(processed_teams)
    
  }, error = function(e) {
    warning(paste("Error processing league", league_id, "teams:", e$message))
    return(NULL)
  })
}

generate_league_csv <- function(teams, league_id, season) {
  # Generate CSV file for league teams
  # Returns file path or NULL on error
  
  tryCatch({
    if (is.null(teams) || length(teams) == 0) {
      return(NULL)
    }
    
    # Convert to data frame format
    team_data <- data.frame(
      TeamID = sapply(teams, function(t) t$id),
      ShortText = sapply(teams, function(t) t$short_name),
      Promotion = sapply(teams, function(t) t$promotion_value),
      InitialELO = sapply(teams, function(t) t$initial_elo),
      stringsAsFactors = FALSE
    )
    
    # Generate temporary file name
    temp_file <- file.path("RCode", paste0("TeamList_", season, "_", get_league_name(league_id), ".csv"))
    
    # Generate CSV
    file_path <- generate_team_list_csv(team_data, season, dirname(temp_file))
    
    return(file_path)
    
  }, error = function(e) {
    warning(paste("Error generating CSV for league", league_id, ":", e$message))
    return(NULL)
  })
}

merge_league_files <- function(league_files, season) {
  # Merge all league files into single team list
  # Returns merged file path or NULL on error
  
  tryCatch({
    if (is.null(league_files) || length(league_files) == 0) {
      return(NULL)
    }
    
    # Read all league files
    all_teams <- data.frame()
    
    for (file in league_files) {
      if (file.exists(file)) {
        league_data <- safe_file_read(file)
        
        if (!is.null(league_data)) {
          all_teams <- rbind(all_teams, league_data)
        }
      }
    }
    
    if (nrow(all_teams) == 0) {
      return(NULL)
    }
    
    # Sort by TeamID
    all_teams <- all_teams[order(all_teams$TeamID), ]
    
    # Generate final merged file
    merged_file <- generate_team_list_csv(all_teams, season)
    
    # Clean up temporary league files
    for (file in league_files) {
      if (file.exists(file) && file != merged_file) {
        file.remove(file)
      }
    }
    
    return(merged_file)
    
  }, error = function(e) {
    warning(paste("Error merging league files:", e$message))
    return(NULL)
  })
}

validate_season_processing <- function(season, team_count_expected = 60) {
  # Validate season processing results
  # Returns validation status
  
  tryCatch({
    # Check if team list file exists
    team_list_file <- paste0("RCode/TeamList_", season, ".csv")
    
    if (!file.exists(team_list_file)) {
      return(list(
        valid = FALSE,
        message = "Team list file not found"
      ))
    }
    
    # Verify file integrity
    integrity_check <- verify_csv_integrity(team_list_file)
    
    if (!integrity_check) {
      return(list(
        valid = FALSE,
        message = "Team list file integrity check failed"
      ))
    }
    
    # Read and validate data
    team_data <- safe_file_read(team_list_file)
    
    if (is.null(team_data)) {
      return(list(
        valid = FALSE,
        message = "Could not read team list file"
      ))
    }
    
    # Check team count
    if (nrow(team_data) < team_count_expected * 0.8) {  # Allow 20% variance
      return(list(
        valid = FALSE,
        message = paste("Team count too low:", nrow(team_data), "expected ~", team_count_expected)
      ))
    }
    
    # Check for required columns
    required_columns <- c("TeamID", "ShortText", "Promotion", "InitialELO")
    missing_columns <- setdiff(required_columns, colnames(team_data))
    
    if (length(missing_columns) > 0) {
      return(list(
        valid = FALSE,
        message = paste("Missing columns:", paste(missing_columns, collapse = ", "))
      ))
    }
    
    # Check for duplicates
    if (any(duplicated(team_data$TeamID))) {
      return(list(
        valid = FALSE,
        message = "Duplicate team IDs found"
      ))
    }
    
    if (any(duplicated(team_data$ShortText))) {
      return(list(
        valid = FALSE,
        message = "Duplicate short names found"
      ))
    }
    
    return(list(
      valid = TRUE,
      message = "Season processing validation passed",
      teams = nrow(team_data)
    ))
    
  }, error = function(e) {
    return(list(
      valid = FALSE,
      message = paste("Validation error:", e$message)
    ))
  })
}

create_processing_report <- function(source_season, target_season, processing_results) {
  # Create processing report for documentation
  # Returns report data structure
  
  tryCatch({
    report <- list(
      timestamp = Sys.time(),
      source_season = source_season,
      target_season = target_season,
      success = processing_results$success,
      seasons_processed = processing_results$seasons_processed,
      files_created = processing_results$files_created,
      total_teams = 0
    )
    
    # Count total teams across all files
    if (!is.null(processing_results$files_created)) {
      for (file in processing_results$files_created) {
        if (file.exists(file)) {
          data <- safe_file_read(file)
          if (!is.null(data)) {
            report$total_teams <- report$total_teams + nrow(data)
          }
        }
      }
    }
    
    # Add error information if failed
    if (!processing_results$success) {
      report$error = processing_results$error
    }
    
    # Save report to file
    report_file <- paste0("processing_report_", source_season, "_to_", target_season, ".json")
    writeLines(jsonlite::toJSON(report, pretty = TRUE), report_file)
    
    cat("Processing report saved to:", report_file, "\n")
    
    return(report)
    
  }, error = function(e) {
    warning("Error creating processing report:", e$message)
    return(NULL)
  })
}

cleanup_processing_artifacts <- function(season) {
  # Clean up temporary files and artifacts
  # Returns number of files cleaned
  
  tryCatch({
    cleanup_patterns <- c(
      paste0("TeamList_", season, "_.*\\.csv"),  # League-specific files
      paste0(".*_backup_.*\\.csv"),              # Backup files
      ".*\\.tmp",                                # Temporary files
      ".*\\.lock"                                # Lock files
    )
    
    total_cleaned <- 0
    
    for (pattern in cleanup_patterns) {
      files <- list.files("RCode", pattern = pattern, full.names = TRUE)
      
      for (file in files) {
        if (file.exists(file)) {
          file.remove(file)
          total_cleaned <- total_cleaned + 1
        }
      }
    }
    
    if (total_cleaned > 0) {
      cat("Cleaned up", total_cleaned, "temporary files\n")
    }
    
    return(total_cleaned)
    
  }, error = function(e) {
    warning("Error cleaning up artifacts:", e$message)
    return(0)
  })
}