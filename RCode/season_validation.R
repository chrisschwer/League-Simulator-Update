# Season Validation Functions
# Validates season completion and ranges for automated season transition

validate_season_completion <- function(season) {
  # Check if season is complete by verifying all matches are finished
  # Throws error if season is not complete
  
  tryCatch({
    cat("Checking if season", season, "is complete...\n")
    
    # Check all three leagues
    leagues <- c("78", "79", "80")  # Bundesliga, 2. Bundesliga, 3. Liga
    total_unfinished <- 0
    leagues_checked <- 0
    
    for (league in leagues) {
      # Fetch all matches for this league and season
      url <- "https://api-football-v1.p.rapidapi.com/v3/fixtures"
      
      response <- httr::GET(
        url,
        query = list(
          league = league,
          season = season
        ),
        httr::add_headers(
          'X-RapidAPI-Key' = Sys.getenv("RAPIDAPI_KEY"),
          'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
        )
      )
      
      if (httr::status_code(response) != 200) {
        warning(paste("Failed to fetch matches for league", league))
        next
      }
      
      content <- httr::content(response, "parsed")
      
      if (is.null(content$response) || length(content$response) == 0) {
        warning(paste("No matches found for league", league, "season", season))
        next
      }
      
      # Count unfinished matches
      for (match in content$response) {
        if (!is.null(match$fixture) && !is.null(match$fixture$status)) {
          status <- match$fixture$status$short
          
          # Check if match is not finished
          if (!status %in% c("FT", "AET", "PEN")) {
            total_unfinished <- total_unfinished + 1
          }
        }
      }
      
      # Mark this league as successfully checked
      leagues_checked <- leagues_checked + 1
    }
    
    # Check if any leagues were successfully validated
    if (leagues_checked == 0) {
      warning("Could not validate any leagues due to API failures")
      return(FALSE)
    }
    
    if (total_unfinished > 0) {
      stop(sprintf("Season %s not finished, no season transition possible.", season))
    }
    
    return(TRUE)
    
  }, error = function(e) {
    if (grepl("not finished", e$message)) {
      stop(e$message)  # Re-throw the specific error
    }
    warning(paste("Error validating season", season, ":", e$message))
    return(FALSE)
  })
}

check_league_completion <- function(league, season) {
  # Basic API call to check if league season is complete
  # Returns results data if available, NULL otherwise
  
  api_key <- Sys.getenv("RAPIDAPI_KEY")
  if (api_key == "") {
    stop("RAPIDAPI_KEY environment variable not set")
  }
  
  url <- "https://api-football-v1.p.rapidapi.com/v3/fixtures"
  
  query_params <- list(
    league = league,
    season = season,
    status = "FT"  # Only finished matches
  )
  
  response <- tryCatch({
    httr::GET(
      url,
      query = query_params,
      httr::add_headers(
        'X-RapidAPI-Key' = api_key,
        'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
      )
    )
  }, error = function(e) {
    stop(paste("API call failed:", e$message))
  })
  
  if (httr::status_code(response) != 200) {
    stop(paste("API returned status", httr::status_code(response)))
  }
  
  content <- httr::content(response, "text", encoding = "UTF-8")
  data <- jsonlite::fromJSON(content)
  
  # Check if we have a reasonable number of finished matches
  if (is.null(data$response) || length(data$response) == 0) {
    return(NULL)
  }
  
  # For a complete season, we expect around 300+ matches per league
  if (length(data$response) < 200) {
    warning(paste("League", league, "season", season, "appears incomplete - only", length(data$response), "matches found"))
  }
  
  return(data$response)
}

validate_season_range <- function(source_season, target_season) {
  # Validate season range is logical and feasible
  # Throws error if invalid
  
  # Convert to numeric for comparison
  source_year <- as.numeric(source_season)
  target_year <- as.numeric(target_season)
  
  # Basic range validation
  if (is.na(source_year) || is.na(target_year)) {
    stop("Seasons must be valid 4-digit years")
  }
  
  if (source_year < 2000 || source_year > 2030) {
    stop("Source season must be between 2000 and 2030")
  }
  
  if (target_year < 2000 || target_year > 2030) {
    stop("Target season must be between 2000 and 2030")
  }
  
  if (source_year >= target_year) {
    stop("Target season must be after source season")
  }
  
  if (target_year - source_year > 10) {
    stop("Season range too large. Maximum 10 seasons supported.")
  }
  
  # Check if source season is complete
  if (!validate_season_completion(source_season)) {
    stop(paste("Source season", source_season, "is not complete or data not available"))
  }
  
  # Warn about existing files
  seasons_to_create <- seq(source_year + 1, target_year)
  existing_files <- c()
  
  for (season in seasons_to_create) {
    file_path <- paste0("RCode/TeamList_", season, ".csv")
    if (file.exists(file_path)) {
      existing_files <- c(existing_files, file_path)
    }
  }
  
  if (length(existing_files) > 0) {
    warning(paste("The following files already exist and will be overwritten:", 
                  paste(existing_files, collapse = ", ")))
  }
  
  return(TRUE)
}

check_existing_files <- function(season) {
  # Check if TeamList file already exists
  # Returns file path if exists, NULL otherwise
  
  file_path <- paste0("RCode/TeamList_", season, ".csv")
  
  if (file.exists(file_path)) {
    return(file_path)
  }
  
  return(NULL)
}

prompt_overwrite_confirmation <- function(file_path) {
  # Prompt for overwrite confirmation
  # Returns TRUE if user confirms overwrite
  
  cat("File already exists:", file_path, "\n")
  
  # Use the input handler if available, otherwise fall back to readline
  if (exists("get_user_input") && is.function(get_user_input)) {
    response <- get_user_input("Overwrite existing file? (y/n): ", default = "n")
    return(tolower(trimws(response)) %in% c("y", "yes"))
  } else if (interactive()) {
    response <- readline("Overwrite existing file? (y/n): ")
    return(tolower(trimws(response)) %in% c("y", "yes"))
  } else {
    # In non-interactive mode, default to not overwriting
    cat("Running in non-interactive mode. Skipping existing file.\n")
    return(FALSE)
  }
}

validate_api_access <- function() {
  # Validate API access and credentials
  # Returns TRUE if API is accessible, FALSE otherwise
  
  api_key <- Sys.getenv("RAPIDAPI_KEY")
  if (api_key == "") {
    stop("RAPIDAPI_KEY environment variable not set")
  }
  
  # Test API access with a simple call
  tryCatch({
    url <- "https://api-football-v1.p.rapidapi.com/v3/leagues"
    
    response <- httr::GET(
      url,
      query = list(id = "78"),  # Bundesliga
      httr::add_headers(
        'X-RapidAPI-Key' = api_key,
        'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
      )
    )
    
    if (httr::status_code(response) == 200) {
      return(TRUE)
    } else {
      warning(paste("API test failed with status", httr::status_code(response)))
      return(FALSE)
    }
    
  }, error = function(e) {
    warning(paste("API access test failed:", e$message))
    return(FALSE)
  })
}

get_seasons_to_process <- function(source_season, target_season) {
  # Get list of seasons that need to be processed
  # Returns vector of season years
  
  source_year <- as.numeric(source_season)
  target_year <- as.numeric(target_season)
  
  return(seq(source_year + 1, target_year))
}

log_validation_results <- function(source_season, target_season, validation_results) {
  # Log validation results for debugging
  # Creates structured log entry
  
  cat("\n=== Season Validation Results ===\n")
  cat("Source Season:", source_season, "\n")
  cat("Target Season:", target_season, "\n")
  cat("Seasons to Process:", length(get_seasons_to_process(source_season, target_season)), "\n")
  
  if (!is.null(validation_results$api_access)) {
    cat("API Access:", ifelse(validation_results$api_access, "✓", "✗"), "\n")
  }
  
  if (!is.null(validation_results$source_complete)) {
    cat("Source Complete:", ifelse(validation_results$source_complete, "✓", "✗"), "\n")
  }
  
  if (!is.null(validation_results$existing_files)) {
    cat("Existing Files:", length(validation_results$existing_files), "\n")
  }
  
  cat("=================================\n\n")
}