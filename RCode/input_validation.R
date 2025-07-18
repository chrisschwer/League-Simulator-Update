# Input Validation Functions
# Validates and sanitizes user input for security and correctness

validate_team_count <- function(file_path) {
  # Validate that the team count is within expected range
  # Returns validation result
  
  tryCatch({
    if (!file.exists(file_path)) {
      return(list(
        valid = FALSE,
        message = "File does not exist"
      ))
    }
    
    # Read the CSV file
    team_data <- read.csv(file_path, sep = ";", stringsAsFactors = FALSE)
    team_count <- nrow(team_data)
    
    # Expected range: 56-62 teams (3 leagues)
    if (team_count < 56) {
      return(list(
        valid = FALSE,
        message = paste("Too few teams:", team_count, "- expected at least 56")
      ))
    }
    
    if (team_count > 62) {
      return(list(
        valid = FALSE,
        message = paste("Too many teams:", team_count, "- expected at most 62")
      ))
    }
    
    return(list(
      valid = TRUE,
      message = paste("Team count valid:", team_count, "teams"),
      team_count = team_count
    ))
    
  }, error = function(e) {
    return(list(
      valid = FALSE,
      message = paste("Error reading file:", e$message)
    ))
  })
}

validate_team_short_name <- function(short_name) {
  # Validate team short name format
  # 3-character uppercase requirement
  
  if (is.null(short_name) || is.na(short_name)) {
    return(list(
      valid = FALSE,
      message = "Short name cannot be NULL or NA"
    ))
  }
  
  # Convert to string and trim
  short_name <- trimws(as.character(short_name))
  
  if (nchar(short_name) == 0) {
    return(list(
      valid = FALSE,
      message = "Short name cannot be empty"
    ))
  }
  
  if (nchar(short_name) != 3) {
    return(list(
      valid = FALSE,
      message = "Short name must be exactly 3 characters"
    ))
  }
  
  # Check for valid characters (letters and numbers only)
  if (!grepl("^[A-Za-z0-9]{3}$", short_name)) {
    return(list(
      valid = FALSE,
      message = "Short name must contain only letters and numbers"
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "Short name is valid",
    sanitized = toupper(short_name)
  ))
}

validate_elo_input <- function(elo_value) {
  # Validate ELO input is numeric and reasonable
  # Range checking and format validation
  
  if (is.null(elo_value) || is.na(elo_value)) {
    return(list(
      valid = FALSE,
      message = "ELO value cannot be NULL or NA"
    ))
  }
  
  # Try to convert to numeric
  if (is.character(elo_value)) {
    elo_numeric <- suppressWarnings(as.numeric(elo_value))
    if (is.na(elo_numeric)) {
      return(list(
        valid = FALSE,
        message = "ELO value must be numeric"
      ))
    }
    elo_value <- elo_numeric
  }
  
  if (!is.numeric(elo_value)) {
    return(list(
      valid = FALSE,
      message = "ELO value must be numeric"
    ))
  }
  
  # Check reasonable range
  if (elo_value < 500 || elo_value > 2500) {
    return(list(
      valid = FALSE,
      message = "ELO value must be between 500 and 2500"
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "ELO value is valid",
    sanitized = as.numeric(elo_value)
  ))
}

sanitize_user_input <- function(input, max_length = 100) {
  # Sanitize user input for security
  # Remove dangerous characters and limit length
  
  if (is.null(input) || is.na(input)) {
    return("")
  }
  
  # Convert to string
  input <- as.character(input)
  
  # Remove potential script injection patterns
  dangerous_patterns <- c(
    "<script[^>]*>.*?</script>",  # Script tags
    "<[^>]*>",                   # HTML tags
    "javascript:",               # JavaScript URLs
    "vbscript:",                 # VBScript URLs
    "data:",                     # Data URLs
    "\\\\",                      # Backslashes
    "\\.\\./",                   # Path traversal
    "\\|",                       # Pipe characters
    ";",                         # Semicolons
    "&",                         # Ampersands
    "\\$",                       # Dollar signs
    "`",                         # Backticks
    "\\{",                       # Curly braces
    "\\}"
  )
  
  for (pattern in dangerous_patterns) {
    input <- gsub(pattern, "", input, ignore.case = TRUE)
  }
  
  # Limit length
  if (nchar(input) > max_length) {
    input <- substr(input, 1, max_length)
  }
  
  # Remove leading/trailing whitespace
  input <- trimws(input)
  
  return(input)
}

validate_season_input <- function(season) {
  # Validate season input format and range
  # Returns validation result
  
  if (is.null(season) || is.na(season)) {
    return(list(
      valid = FALSE,
      message = "Season cannot be NULL or NA"
    ))
  }
  
  # Convert to string and sanitize
  season <- sanitize_user_input(as.character(season))
  
  if (nchar(season) == 0) {
    return(list(
      valid = FALSE,
      message = "Season cannot be empty"
    ))
  }
  
  # Check format (4-digit year)
  if (!grepl("^[0-9]{4}$", season)) {
    return(list(
      valid = FALSE,
      message = "Season must be a 4-digit year (e.g., 2024)"
    ))
  }
  
  # Check reasonable range
  year <- as.numeric(season)
  if (year < 2000 || year > 2030) {
    return(list(
      valid = FALSE,
      message = "Season must be between 2000 and 2030"
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "Season is valid",
    sanitized = season
  ))
}

validate_file_path <- function(file_path, allow_create = TRUE) {
  # Validate file path for security
  # Prevents path traversal attacks
  
  if (is.null(file_path) || is.na(file_path)) {
    return(list(
      valid = FALSE,
      message = "File path cannot be NULL or NA"
    ))
  }
  
  # Sanitize path
  file_path <- sanitize_user_input(file_path, max_length = 256)
  
  if (nchar(file_path) == 0) {
    return(list(
      valid = FALSE,
      message = "File path cannot be empty"
    ))
  }
  
  # Check for path traversal attempts
  if (grepl("\\.\\.", file_path)) {
    return(list(
      valid = FALSE,
      message = "Path traversal not allowed"
    ))
  }
  
  # Check for absolute paths outside allowed directories
  if (grepl("^/", file_path) && !grepl("^/tmp/", file_path) && !grepl("RCode/", file_path)) {
    return(list(
      valid = FALSE,
      message = "Absolute paths not allowed"
    ))
  }
  
  # Check for dangerous file extensions
  dangerous_extensions <- c("\\.exe$", "\\.bat$", "\\.sh$", "\\.ps1$", "\\.com$", "\\.scr$")
  for (ext in dangerous_extensions) {
    if (grepl(ext, file_path, ignore.case = TRUE)) {
      return(list(
        valid = FALSE,
        message = "Dangerous file extension not allowed"
      ))
    }
  }
  
  # Check if file exists (if not allowing creation)
  if (!allow_create && !file.exists(file_path)) {
    return(list(
      valid = FALSE,
      message = "File does not exist"
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "File path is valid",
    sanitized = file_path
  ))
}

validate_league_id <- function(league_id) {
  # Validate league ID
  # Must be one of the supported leagues
  
  if (is.null(league_id) || is.na(league_id)) {
    return(list(
      valid = FALSE,
      message = "League ID cannot be NULL or NA"
    ))
  }
  
  # Convert to string and sanitize
  league_id <- sanitize_user_input(as.character(league_id))
  
  # Check against supported leagues
  valid_leagues <- c("78", "79", "80")
  
  if (!league_id %in% valid_leagues) {
    return(list(
      valid = FALSE,
      message = paste("League ID must be one of:", paste(valid_leagues, collapse = ", "))
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "League ID is valid",
    sanitized = league_id
  ))
}

validate_team_name <- function(team_name) {
  # Validate team name input
  # Ensures reasonable length and character set
  
  if (is.null(team_name) || is.na(team_name)) {
    return(list(
      valid = FALSE,
      message = "Team name cannot be NULL or NA"
    ))
  }
  
  # Sanitize team name
  team_name <- sanitize_user_input(team_name, max_length = 50)
  
  if (nchar(team_name) == 0) {
    return(list(
      valid = FALSE,
      message = "Team name cannot be empty"
    ))
  }
  
  if (nchar(team_name) < 2) {
    return(list(
      valid = FALSE,
      message = "Team name must be at least 2 characters"
    ))
  }
  
  # Check for valid characters (letters, numbers, spaces, common punctuation)
  if (!grepl("^[A-Za-z0-9 .'\\-]+$", team_name)) {
    return(list(
      valid = FALSE,
      message = "Team name contains invalid characters"
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "Team name is valid",
    sanitized = team_name
  ))
}

validate_promotion_value <- function(promotion_value) {
  # Validate promotion value
  # Must be 0 or -50 for Liga3 second teams
  
  if (is.null(promotion_value) || is.na(promotion_value)) {
    return(list(
      valid = FALSE,
      message = "Promotion value cannot be NULL or NA"
    ))
  }
  
  # Convert to numeric if string
  if (is.character(promotion_value)) {
    promotion_numeric <- suppressWarnings(as.numeric(promotion_value))
    if (is.na(promotion_numeric)) {
      return(list(
        valid = FALSE,
        message = "Promotion value must be numeric"
      ))
    }
    promotion_value <- promotion_numeric
  }
  
  if (!is.numeric(promotion_value)) {
    return(list(
      valid = FALSE,
      message = "Promotion value must be numeric"
    ))
  }
  
  # Check valid values
  valid_values <- c(0, -50)
  if (!promotion_value %in% valid_values) {
    return(list(
      valid = FALSE,
      message = "Promotion value must be 0 or -50"
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "Promotion value is valid",
    sanitized = as.numeric(promotion_value)
  ))
}

validate_command_line_args <- function(args) {
  # Validate command line arguments
  # Ensures correct number and format of arguments
  
  if (is.null(args) || length(args) == 0) {
    return(list(
      valid = FALSE,
      message = "No arguments provided"
    ))
  }
  
  if (length(args) != 2) {
    return(list(
      valid = FALSE,
      message = "Exactly 2 arguments required: source_season target_season"
    ))
  }
  
  # Validate source season
  source_validation <- validate_season_input(args[1])
  if (!source_validation$valid) {
    return(list(
      valid = FALSE,
      message = paste("Source season invalid:", source_validation$message)
    ))
  }
  
  # Validate target season
  target_validation <- validate_season_input(args[2])
  if (!target_validation$valid) {
    return(list(
      valid = FALSE,
      message = paste("Target season invalid:", target_validation$message)
    ))
  }
  
  # Check season order
  source_year <- as.numeric(source_validation$sanitized)
  target_year <- as.numeric(target_validation$sanitized)
  
  if (source_year >= target_year) {
    return(list(
      valid = FALSE,
      message = "Target season must be after source season"
    ))
  }
  
  return(list(
    valid = TRUE,
    message = "Command line arguments are valid",
    source_season = source_validation$sanitized,
    target_season = target_validation$sanitized
  ))
}

log_validation_error <- function(validation_result, context = NULL) {
  # Log validation errors for debugging
  # Creates structured error log
  
  if (validation_result$valid) {
    return()  # No error to log
  }
  
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  log_entry <- list(
    timestamp = timestamp,
    validation_error = validation_result$message,
    context = context
  )
  
  # Write to validation error log
  error_log_file <- "validation_errors.log"
  
  if (file.exists(error_log_file)) {
    # Append to existing log
    existing_log <- readLines(error_log_file)
    new_log <- c(existing_log, jsonlite::toJSON(log_entry))
    writeLines(new_log, error_log_file)
  } else {
    # Create new log
    writeLines(jsonlite::toJSON(log_entry), error_log_file)
  }
}

create_validation_report <- function(validations) {
  # Create validation report for multiple inputs
  # Returns summary of all validation results
  
  total_validations <- length(validations)
  passed_validations <- sum(sapply(validations, function(v) v$valid))
  failed_validations <- total_validations - passed_validations
  
  report <- list(
    total = total_validations,
    passed = passed_validations,
    failed = failed_validations,
    success_rate = round((passed_validations / total_validations) * 100, 2),
    details = validations
  )
  
  return(report)
}