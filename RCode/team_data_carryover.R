# Team Data Carryover Module
# Handles loading and matching team data from previous seasons

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

# Source required modules
source_with_fallback("RCode/file_operations.R")

#' Load team list from previous season
#' 
#' Loads TeamList for specified season, checking for most recent merged file first
#' 
#' @param season The season year to load
#' @return Data frame of team data or NULL if not found
#' @export
load_previous_team_list <- function(season) {
  # Load TeamList for specified season
  # Returns data frame or NULL if not found
  # Checks for most recent merged file first, then original file
  
  tryCatch({
    # First check for a merged file that might have been created during current processing
    merged_file <- paste0("RCode/TeamList_", season, ".csv")
    
    # Check if we have temporary files from current processing (indicates season is being processed)
    temp_files <- list.files("RCode", pattern = paste0("TeamList_", season, "_League.*_temp\\.csv$"), full.names = TRUE)
    
    if (length(temp_files) > 0) {
      # We have temporary files, merge them and use the result
      cat("Found temporary files for season", season, ", merging for carryover\n")
      
      all_teams <- data.frame()
      for (file in temp_files) {
        if (file.exists(file)) {
          cat("Reading temporary file:", basename(file), "\n")
          league_data <- read.csv(file, sep = ";", stringsAsFactors = FALSE)
          if (!is.null(league_data) && nrow(league_data) > 0) {
            all_teams <- rbind(all_teams, league_data)
          }
        }
      }
      
      if (nrow(all_teams) > 0) {
        return(all_teams)
      }
    }
    
    # Fall back to original merged file
    if (!file.exists(merged_file)) {
      warning(paste("TeamList file not found for season", season))
      return(NULL)
    }
    
    # Read using safe file read
    team_data <- safe_file_read(merged_file, sep = ";", header = TRUE)
    
    if (is.null(team_data)) {
      warning(paste("Could not read TeamList for season", season))
      return(NULL)
    }
    
    # Validate required columns
    required_cols <- c("TeamID", "ShortText", "Promotion", "InitialELO")
    if (!all(required_cols %in% colnames(team_data))) {
      warning(paste("TeamList for season", season, "missing required columns"))
      return(NULL)
    }
    
    return(team_data)
    
  }, error = function(e) {
    warning(paste("Error loading TeamList for season", season, ":", e$message))
    return(NULL)
  })
}

#' Get existing team data from previous season
#' 
#' Retrieves team data from previous season by TeamID
#' 
#' @param team_id The team ID to look up
#' @param previous_team_list Data frame of previous season teams
#' @return List with short_name and promotion_value or NULL
#' @export
get_existing_team_data <- function(team_id, previous_team_list) {
  # Get team data from previous season by TeamID
  # Returns list with short_name and promotion_value or NULL
  
  if (is.null(previous_team_list) || nrow(previous_team_list) == 0) {
    return(NULL)
  }
  
  # Find team by ID
  team_row <- previous_team_list[previous_team_list$TeamID == team_id, ]
  
  if (nrow(team_row) == 0) {
    return(NULL)
  }
  
  return(list(
    short_name = as.character(team_row$ShortText[1]),
    promotion_value = as.numeric(team_row$Promotion[1])
  ))
}

build_team_lookup_table <- function(previous_team_list) {
  # Build lookup table for fast team data access
  # Returns named list: TeamID -> list(short_name, promotion_value)
  
  if (is.null(previous_team_list) || nrow(previous_team_list) == 0) {
    return(list())
  }
  
  lookup <- list()
  
  for (i in 1:nrow(previous_team_list)) {
    team_id <- as.character(previous_team_list$TeamID[i])
    lookup[[team_id]] <- list(
      short_name = as.character(previous_team_list$ShortText[i]),
      promotion_value = as.numeric(previous_team_list$Promotion[i])
    )
  }
  
  return(lookup)
}

#' Validate uniqueness of short names
#' 
#' Checks if all team short names are unique
#' 
#' @param short_names Vector of team short names
#' @return Logical indicating if all names are unique
#' @export
validate_short_name_uniqueness <- function(short_names) {
  # Check if all short names are unique
  # Returns validation result
  
  duplicates <- short_names[duplicated(short_names)]
  
  if (length(duplicates) > 0) {
    return(list(
      valid = FALSE,
      message = paste("Duplicate short names found:", paste(unique(duplicates), collapse = ", ")),
      duplicates = unique(duplicates)
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "All short names are unique"
  ))
}

merge_team_data_with_carryover <- function(new_teams, previous_team_list, final_elos) {
  # Merge new team data with carryover from previous season
  # Returns merged team list
  
  if (is.null(previous_team_list)) {
    warning("No previous team list available for carryover")
    return(new_teams)
  }
  
  # Build lookup table for efficiency
  team_lookup <- build_team_lookup_table(previous_team_list)
  
  # Process each team
  for (i in seq_along(new_teams)) {
    team <- new_teams[[i]]
    team_id_str <- as.character(team$id)
    
    # Check if team existed in previous season
    if (team_id_str %in% names(team_lookup)) {
      # Carry over short name and promotion value
      previous_data <- team_lookup[[team_id_str]]
      new_teams[[i]]$short_name <- previous_data$short_name
      new_teams[[i]]$promotion_value <- previous_data$promotion_value
      
      # Get final ELO if available
      if (!is.null(final_elos)) {
        team_elo <- final_elos$FinalELO[final_elos$TeamID == team$id]
        if (length(team_elo) > 0) {
          new_teams[[i]]$initial_elo <- team_elo[1]
        }
      }
    }
  }
  
  return(new_teams)
}

#' Ensure unique short names for teams
#' 
#' Modifies duplicate short names to ensure uniqueness by appending suffixes
#' 
#' @param teams Data frame containing team data with ShortText column
#' @return Data frame with unique short names
#' @export
ensure_unique_short_names <- function(teams) {
  # Ensure all teams have unique short names
  # Returns teams with guaranteed unique short names
  
  short_names <- sapply(teams, function(t) t$short_name)
  validation <- validate_short_name_uniqueness(short_names)
  
  if (!validation$valid) {
    # Fix duplicates by appending numbers
    for (dup in validation$duplicates) {
      indices <- which(short_names == dup)
      if (length(indices) > 1) {
        # Keep first occurrence, modify others
        for (j in 2:length(indices)) {
          idx <- indices[j]
          counter <- 1
          new_name <- paste0(substr(dup, 1, 2), counter)
          
          # Find unique name
          while (new_name %in% short_names) {
            counter <- counter + 1
            new_name <- paste0(substr(dup, 1, 2), counter)
          }
          
          teams[[idx]]$short_name <- new_name
          short_names[idx] <- new_name
        }
      }
    }
  }
  
  return(teams)
}
