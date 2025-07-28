# Season Processing Pipeline
# Main processing logic for season transitions

# Helper function for robust sourcing
source_with_fallback <- function(path) {
  if (requireNamespace("here", quietly = TRUE)) {
    source(here::here(path))
  } else {
    # Fallback: try from project root or current directory
    if (file.exists(path)) {
      source(path)
    } else if (file.exists(file.path("..", "..", path))) {
      source(file.path("..", "..", path))
    } else {
      stop(paste("Cannot find", path))
    }
  }
}

# Source team data carryover module
source_with_fallback("RCode/team_data_carryover.R")

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

#' Process a single season transition
#' 
#' Handles team discovery and ELO assignment for a single season
#' 
#' @param season The target season year
#' @param previous_season The source season year
#' @return A list with success status, files created, teams processed, and any error
#' @export
process_single_season <- function(season, previous_season) {
  # Process transition for single season
  # Handles team discovery and ELO assignment
  
  tryCatch({
    cat("\n=== Processing Season", season, "===\n")
    
    # Validate previous season is complete before processing
    cat("Validating previous season completion\n")
    if (!validate_season_completion(previous_season)) {
      stop(sprintf("Season %s not finished, no season transition possible.", previous_season))
    }
    
    # Load previous season team list for carryover
    cat("Loading previous season team data\n")
    previous_team_list <- load_previous_team_list(previous_season)
    
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
        liga3_baseline,
        previous_team_list
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
    cat("Merging all leagues into single team list\n")
    merged_file <- merge_league_files(files_created, season)
    
    if (!is.null(merged_file)) {
      files_created <- c(files_created, merged_file)
      
      # Validate team count
      team_count_validation <- validate_team_count(merged_file)
      if (!team_count_validation$valid) {
        warning(team_count_validation$message)
      }
    } else {
      warning("Failed to merge league files")
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

#' Process teams for a specific league
#' 
#' Processes team data for a league including ELO assignment and name handling
#' 
#' @param teams The team data to process
#' @param league_id The ID of the league
#' @param season The season year
#' @param final_elos Final ELO ratings from previous season
#' @param liga3_baseline Baseline ELO for Liga 3 teams
#' @param previous_team_list Previous season team list for carryover
#' @return Processed team data frame
#' @export
process_league_teams <- function(teams, league_id, season, final_elos, liga3_baseline, previous_team_list = NULL) {
  # Process teams for a specific league
  # Handles ELO assignment and user prompts with carryover from previous seasons
  
  tryCatch({
    processed_teams <- list()
    existing_short_names <- c()
    
    for (i in seq_along(teams)) {
      team <- teams[[i]]
      
      # Check if team existed in previous season - prioritize previous_team_list over final_elos
      team_exists <- FALSE
      team_elo <- NULL
      previous_data <- NULL
      
      # First check previous_team_list (contains teams from current processing)
      if (!is.null(previous_team_list)) {
        previous_data <- get_existing_team_data(team$id, previous_team_list)
        if (!is.null(previous_data)) {
          team_exists <- TRUE
          # Get final ELO if available
          elo_row <- final_elos$FinalELO[final_elos$TeamID == team$id]
          if (length(elo_row) > 0) {
            team_elo <- elo_row[1]
          }
        }
      }
      
      # Fall back to final_elos check if not found in previous_team_list
      if (!team_exists) {
        team_elo <- final_elos$FinalELO[final_elos$TeamID == team$id]
        if (length(team_elo) > 0) {
          team_exists <- TRUE
        }
      }
      
      if (!team_exists) {
        # New team - need user input
        cat("\n--- New Team Detected ---\n")
        cat("Team ID:", team$id, "\n")
        cat("Team Name:", team$name, "\n")
        cat("League:", get_league_name(league_id), "\n")
        
        # Get team information interactively, pass baseline for Liga3
        team_info <- prompt_for_team_info(team$name, league_id, existing_short_names, liga3_baseline)
        
        # Apply second team conversion if needed
        final_short_name <- convert_second_team_short_name(
          team_info$short_name,
          team$is_second_team,
          team_info$promotion_value
        )
        
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = final_short_name,
          initial_elo = team_info$initial_elo,
          promotion_value = team_info$promotion_value
        )
        
        existing_short_names <- c(existing_short_names, final_short_name)
        
      } else {
        # Existing team - use data from previous season (already found above)
        if (!is.null(previous_data)) {
          # Use carryover data from previous season
          short_name <- previous_data$short_name
          promotion_value <- previous_data$promotion_value
        } else {
          # Fallback: generate new data if not found in previous season
          warning(paste("Team", team$id, "-", team$name, "not found in previous season, generating new data"))
          short_name <- get_team_short_name(team$name)
          
          # Ensure uniqueness
          if (short_name %in% existing_short_names) {
            short_name <- generate_unique_short_name(short_name, existing_short_names)
          }
          
          # Determine promotion value
          promotion_value <- ifelse(team$is_second_team, -50, 0)
        }
        
        # Apply second team conversion if needed
        final_short_name <- convert_second_team_short_name(
          short_name,
          team$is_second_team,
          promotion_value
        )
        
        # Use team_elo if available, otherwise use baseline
        if (!is.null(team_elo) && length(team_elo) > 0) {
          initial_elo <- team_elo[1]
          cat("Team", team$id, "(", team$name, "): Using final ELO", round(initial_elo, 2), "\n")
        } else {
          initial_elo <- ifelse(league_id == 80, liga3_baseline, 1500)
          cat("Team", team$id, "(", team$name, "): Using baseline ELO", round(initial_elo, 2), "\n")
        }
        
        processed_team <- list(
          id = team$id,
          name = team$name,
          short_name = final_short_name,
          initial_elo = initial_elo,
          promotion_value = promotion_value
        )
        
        existing_short_names <- c(existing_short_names, final_short_name)
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
    
    # Generate temporary file name with unique league identifier
    temp_filename <- paste0("TeamList_", season, "_League", league_id, "_temp.csv")
    temp_file <- file.path("RCode", temp_filename)
    
    # Write CSV directly with league-specific name
    write.table(team_data, temp_file, sep = ";", row.names = FALSE, quote = FALSE)
    
    file_path <- temp_file
    
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
    
    # Filter only temp league files
    temp_league_files <- league_files[grepl("_League[0-9]+_temp\\.csv$", league_files)]
    
    if (length(temp_league_files) == 0) {
      warning("No temporary league files found to merge")
      return(NULL)
    }
    
    cat("Merging", length(temp_league_files), "league files\n")
    
    # Read all league files
    all_teams <- data.frame()
    
    for (file in temp_league_files) {
      if (file.exists(file)) {
        cat("Reading:", basename(file), "\n")
        league_data <- read.csv(file, sep = ";", stringsAsFactors = FALSE)
        
        if (!is.null(league_data) && nrow(league_data) > 0) {
          all_teams <- rbind(all_teams, league_data)
        }
      }
    }
    
    if (nrow(all_teams) == 0) {
      warning("No team data found in league files")
      return(NULL)
    }
    
    cat("Total teams to merge:", nrow(all_teams), "\n")
    
    # Remove duplicate TeamIDs (keep first occurrence)
    if (any(duplicated(all_teams$TeamID))) {
      duplicate_ids <- all_teams$TeamID[duplicated(all_teams$TeamID)]
      cat("Warning: Removing duplicate TeamIDs:", paste(unique(duplicate_ids), collapse = ", "), "\n")
      all_teams <- all_teams[!duplicated(all_teams$TeamID), ]
      cat("Teams after deduplication:", nrow(all_teams), "\n")
    }
    
    # Fix duplicate ShortTexts by appending numbers
    if (any(duplicated(all_teams$ShortText))) {
      duplicate_short_texts <- all_teams$ShortText[duplicated(all_teams$ShortText)]
      cat("Warning: Fixing duplicate ShortTexts:", paste(unique(duplicate_short_texts), collapse = ", "), "\n")
      
      for (dup_name in unique(duplicate_short_texts)) {
        dup_indices <- which(all_teams$ShortText == dup_name)
        if (length(dup_indices) > 1) {
          # Keep first occurrence, modify others
          for (i in 2:length(dup_indices)) {
            idx <- dup_indices[i]
            counter <- 1
            new_name <- paste0(substr(dup_name, 1, 2), counter)
            
            # Make sure the new name is unique
            while (new_name %in% all_teams$ShortText) {
              counter <- counter + 1
              new_name <- paste0(substr(dup_name, 1, 2), counter)
            }
            
            all_teams$ShortText[idx] <- new_name
            cat("  Renamed", dup_name, "to", new_name, "for TeamID", all_teams$TeamID[idx], "\n")
          }
        }
      }
    }
    
    # Sort by TeamID
    all_teams <- all_teams[order(all_teams$TeamID), ]
    
    # Generate final merged file
    cat("Generating final merged file for season", season, "\n")
    merged_file <- generate_team_list_csv(all_teams, season)
    
    if (is.null(merged_file)) {
      warning("Failed to generate merged file")
      return(NULL)
    }
    
    cat("Merged file created:", merged_file, "\n")
    
    # Clean up temporary league files
    for (file in temp_league_files) {
      if (file.exists(file)) {
        file.remove(file)
        cat("Removed temp file:", basename(file), "\n")
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