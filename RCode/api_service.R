# API Service Layer
# Handles API calls to fetch team data and manage authentication

fetch_teams_from_api <- function(league_id, season) {
  # Fetch teams from api-football endpoint
  # Returns list of team objects with id, name, and logo
  
  tryCatch({
    # Rate limiting
    Sys.sleep(1)  # Basic rate limiting
    
    api_key <- Sys.getenv("RAPIDAPI_KEY")
    if (api_key == "") {
      stop("RAPIDAPI_KEY environment variable not set")
    }
    
    url <- "https://api-football-v1.p.rapidapi.com/v3/teams"
    
    query_params <- list(
      league = league_id,
      season = season
    )
    
    cat("Fetching teams for league", league_id, "season", season, "\n")
    
    response <- httr::GET(
      url,
      query = query_params,
      httr::add_headers(
        'X-RapidAPI-Key' = api_key,
        'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
      )
    )
    
    # Handle API errors
    if (httr::status_code(response) != 200) {
      error_msg <- paste("API call failed with status", httr::status_code(response))
      
      if (httr::status_code(response) == 429) {
        error_msg <- paste(error_msg, "- Rate limit exceeded")
      } else if (httr::status_code(response) == 401) {
        error_msg <- paste(error_msg, "- Authentication failed")
      }
      
      stop(error_msg)
    }
    
    # Parse response
    content <- httr::content(response, "text", encoding = "UTF-8")
    data <- jsonlite::fromJSON(content)
    
    if (is.null(data$response) || length(data$response) == 0) {
      warning(paste("No teams found for league", league_id, "season", season))
      return(NULL)
    }
    
    # Transform API response to internal format
    teams <- transform_api_team_data(data$response)
    
    cat("Retrieved", length(teams), "teams for league", league_id, "\n")
    
    return(teams)
    
  }, error = function(e) {
    stop(paste("Error fetching teams for league", league_id, "season", season, ":", e$message))
  })
}

transform_api_team_data <- function(api_response) {
  # Transform API response to internal format
  # Handles missing data and formatting
  
  tryCatch({
    teams <- list()
    
    for (i in 1:length(api_response$team$id)) {
      team <- list(
        id = api_response$team$id[i],
        name = api_response$team$name[i],
        logo = api_response$team$logo[i],
        founded = api_response$team$founded[i],
        country = api_response$team$country[i]
      )
      
      # Handle missing data
      if (is.null(team$name) || is.na(team$name)) {
        team$name <- paste("Team", team$id)
      }
      
      if (is.null(team$logo) || is.na(team$logo)) {
        team$logo <- ""
      }
      
      # Detect second teams
      team$is_second_team <- detect_second_teams(team$name)
      
      teams[[i]] <- team
    }
    
    return(teams)
    
  }, error = function(e) {
    stop(paste("Error transforming API team data:", e$message))
  })
}

detect_second_teams <- function(team_name) {
  # Detect second teams (II, 2, etc.)
  # Returns TRUE for second teams
  
  if (is.null(team_name) || is.na(team_name)) {
    return(FALSE)
  }
  
  # Common patterns for second teams
  second_team_patterns <- c(
    " II$",      # Team II
    " 2$",       # Team 2
    " U21$",     # U21 teams
    " B$",       # Team B
    " Reserve$", # Reserve teams
    "\\bII\\b",  # II anywhere in name
    "\\b2\\b"    # 2 anywhere in name (be careful with this)
  )
  
  for (pattern in second_team_patterns) {
    if (grepl(pattern, team_name, ignore.case = TRUE)) {
      return(TRUE)
    }
  }
  
  return(FALSE)
}

get_league_name <- function(league_id) {
  # Get human-readable league name
  # Returns league name string
  
  league_names <- list(
    "78" = "Bundesliga",
    "79" = "2. Bundesliga", 
    "80" = "3. Liga"
  )
  
  if (league_id %in% names(league_names)) {
    return(league_names[[league_id]])
  } else {
    return(paste("League", league_id))
  }
}

validate_team_data <- function(teams) {
  # Validate team data for completeness
  # Returns validation results
  
  if (is.null(teams) || length(teams) == 0) {
    return(list(
      valid = FALSE,
      message = "No teams data provided"
    ))
  }
  
  # Check for required fields
  required_fields <- c("id", "name")
  missing_fields <- c()
  
  for (team in teams) {
    for (field in required_fields) {
      if (is.null(team[[field]]) || is.na(team[[field]])) {
        missing_fields <- c(missing_fields, paste("Team", team$id, "missing", field))
      }
    }
  }
  
  # Check for duplicate IDs
  team_ids <- sapply(teams, function(t) t$id)
  duplicate_ids <- team_ids[duplicated(team_ids)]
  
  validation_results <- list(
    valid = length(missing_fields) == 0 && length(duplicate_ids) == 0,
    total_teams = length(teams),
    missing_fields = missing_fields,
    duplicate_ids = duplicate_ids,
    second_teams = sum(sapply(teams, function(t) t$is_second_team))
  )
  
  if (!validation_results$valid) {
    validation_results$message <- paste(
      "Validation failed:",
      length(missing_fields), "missing fields,",
      length(duplicate_ids), "duplicate IDs"
    )
  } else {
    validation_results$message <- paste(
      "Validation passed:",
      validation_results$total_teams, "teams,",
      validation_results$second_teams, "second teams"
    )
  }
  
  return(validation_results)
}

fetch_all_leagues_teams <- function(season) {
  # Fetch teams for all three leagues
  # Returns list organized by league
  
  leagues <- list(
    "78" = "Bundesliga",
    "79" = "2. Bundesliga",
    "80" = "3. Liga"
  )
  
  all_teams <- list()
  
  for (league_id in names(leagues)) {
    cat("\n--- Fetching", leagues[[league_id]], "teams ---\n")
    
    teams <- tryCatch({
      fetch_teams_from_api(league_id, season)
    }, error = function(e) {
      warning(paste("Failed to fetch teams for league", league_id, ":", e$message))
      return(NULL)
    })
    
    if (!is.null(teams)) {
      # Validate team data
      validation <- validate_team_data(teams)
      cat(validation$message, "\n")
      
      if (!validation$valid) {
        warning(paste("Team data validation failed for league", league_id))
      }
      
      all_teams[[league_id]] <- teams
    }
  }
  
  return(all_teams)
}

get_team_short_name <- function(team_name) {
  # Generate short name from full team name
  # Returns 3-character code
  
  if (is.null(team_name) || is.na(team_name)) {
    return("UNK")
  }
  
  # Common team name mappings
  short_name_mappings <- list(
    "FC Bayern München" = "FCB",
    "Borussia Dortmund" = "BVB",
    "Borussia Mönchengladbach" = "BMG",
    "Bayer 04 Leverkusen" = "B04",
    "RB Leipzig" = "RBL",
    "Eintracht Frankfurt" = "SGE",
    "SC Freiburg" = "SCF",
    "VfL Wolfsburg" = "WOB",
    "TSG 1899 Hoffenheim" = "HOF",
    "1. FC Union Berlin" = "FCU",
    "VfB Stuttgart" = "STU",
    "1. FSV Mainz 05" = "M05",
    "FC Schalke 04" = "S04",
    "Hertha BSC" = "BSC",
    "Werder Bremen" = "BRE",
    "1. FC Köln" = "FCK",
    "FC Augsburg" = "FCA",
    "Arminia Bielefeld" = "DSC",
    "SpVgg Greuther Fürth" = "SGF",
    "VfL Bochum" = "BOC"
  )
  
  # Check if we have a direct mapping
  if (team_name %in% names(short_name_mappings)) {
    return(short_name_mappings[[team_name]])
  }
  
  # Generate short name from team name
  # Remove common prefixes and suffixes
  clean_name <- gsub("^(FC|1\\.|SV|VfL|TSG|SpVgg|Borussia|Eintracht)\\s+", "", team_name)
  clean_name <- gsub("\\s+(München|Berlin|Frankfurt|Dortmund|Leverkusen|e\\.V\\.)$", "", clean_name)
  
  # Take first 3 characters of significant words
  words <- strsplit(clean_name, "\\s+")[[1]]
  if (length(words) >= 1) {
    # Take first 3 characters of first word
    short_name <- toupper(substr(words[1], 1, 3))
    return(short_name)
  }
  
  # Fallback
  return(toupper(substr(team_name, 1, 3)))
}

check_api_rate_limit <- function() {
  # Check API rate limit status
  # Returns rate limit information
  
  tryCatch({
    api_key <- Sys.getenv("RAPIDAPI_KEY")
    if (api_key == "") {
      return(list(error = "RAPIDAPI_KEY not set"))
    }
    
    # Make a simple API call to check rate limit headers
    url <- "https://api-football-v1.p.rapidapi.com/v3/status"
    
    response <- httr::GET(
      url,
      httr::add_headers(
        'X-RapidAPI-Key' = api_key,
        'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
      )
    )
    
    # Extract rate limit headers
    headers <- httr::headers(response)
    
    rate_limit_info <- list(
      status_code = httr::status_code(response),
      requests_remaining = headers$`x-ratelimit-requests-remaining`,
      requests_limit = headers$`x-ratelimit-requests-limit`,
      quota_used = headers$`x-ratelimit-quota-used`,
      quota_limit = headers$`x-ratelimit-quota-limit`
    )
    
    return(rate_limit_info)
    
  }, error = function(e) {
    return(list(error = paste("Failed to check rate limit:", e$message)))
  })
}

log_api_usage <- function(endpoint, league_id, season, success = TRUE) {
  # Log API usage for monitoring
  # Helps track API calls and debug issues
  
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  log_entry <- data.frame(
    timestamp = timestamp,
    endpoint = endpoint,
    league_id = league_id,
    season = season,
    success = success,
    stringsAsFactors = FALSE
  )
  
  # Append to log file
  log_file <- "api_usage.log"
  
  if (file.exists(log_file)) {
    write.table(log_entry, log_file, append = TRUE, col.names = FALSE, row.names = FALSE, sep = "\t")
  } else {
    write.table(log_entry, log_file, append = FALSE, col.names = TRUE, row.names = FALSE, sep = "\t")
  }
}