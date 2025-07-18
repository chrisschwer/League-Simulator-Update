# Interactive User Interface
# Handles user prompts, input validation, and progress display

# Source the input handler module
# Define null coalesce operator
`%||%` <- function(a, b) if (is.null(a)) b else a

# Try to source input handler from multiple possible locations
input_handler_sourced <- FALSE

# Try relative to current file
if (!input_handler_sourced && file.exists("input_handler.R")) {
  source("input_handler.R")
  input_handler_sourced <- TRUE
}

# Try in RCode directory
if (!input_handler_sourced) {
  rcode_path <- file.path("RCode", "input_handler.R")
  if (file.exists(rcode_path)) {
    source(rcode_path)
    input_handler_sourced <- TRUE
  }
}

# Try relative to script location
if (!input_handler_sourced) {
  script_dir <- tryCatch({
    dirname(sys.frame(1)$ofile)
  }, error = function(e) NULL)
  
  if (!is.null(script_dir)) {
    handler_path <- file.path(script_dir, "input_handler.R")
    if (file.exists(handler_path)) {
      source(handler_path)
      input_handler_sourced <- TRUE
    }
  }
}

# Check if we should use interactive mode
check_interactive_mode <- function() {
  # Check if explicitly non-interactive
  if (getOption("season_transition.non_interactive", FALSE)) {
    return(FALSE)
  }
  
  # If not explicitly non-interactive, we require interactive mode
  # This makes interactive the default
  return(TRUE)
}

# Require interactive mode or fail
require_interactive_mode <- function() {
  if (!check_interactive_mode()) {
    return(FALSE)  # Non-interactive mode explicitly enabled
  }
  
  # Check if we can actually be interactive
  if (!interactive()) {
    # Check for terminal
    if (!isatty(stdin())) {
      stop("Terminal required for interactive mode. Use --non-interactive flag for automated runs.")
    }
  }
  
  return(TRUE)
}

prompt_for_team_info <- function(team_name, league, existing_short_names = NULL, baseline = NULL, retry_count = 0) {
  # Interactive prompt for new team information
  # Validates input and provides defaults with optional baseline for Liga3
  
  # Maximum retry limit to prevent infinite loops
  MAX_RETRIES <- 10
  if (retry_count >= MAX_RETRIES) {
    stop("Maximum retry limit reached for team information input")
  }
  
  cat("\n=== New Team Information Required ===\n")
  cat("Team Name:", team_name, "\n")
  cat("League:", get_league_name(league), "\n")
  
  # Get short name
  short_name <- get_team_short_name_interactive(team_name, existing_short_names)
  
  # Get initial ELO (pass baseline for Liga3)
  initial_elo <- get_initial_elo_interactive(league, baseline)
  
  # Get promotion value (only for Liga3)
  promotion_value <- get_promotion_value_interactive(team_name, league)
  
  # Confirmation
  cat("\n--- Team Information Summary ---\n")
  cat("Team Name:", team_name, "\n")
  cat("Short Name:", short_name, "\n")
  cat("Initial ELO:", initial_elo, "\n")
  cat("Promotion Value:", promotion_value, "\n")
  
  if (can_accept_input()) {
    confirmed <- confirm_action("Is this information correct? (y/n): ", default = "y")
    if (!confirmed) {
      cat("Please re-enter team information.\n")
      return(prompt_for_team_info(team_name, league, existing_short_names, baseline, retry_count + 1))
    }
  }
  
  # Apply second team conversion if needed
  if (promotion_value == -50) {
    short_name <- convert_second_team_short_name(short_name, TRUE, promotion_value)
  }
  
  return(list(
    name = team_name,
    short_name = short_name,
    initial_elo = initial_elo,
    promotion_value = promotion_value
  ))
}

get_team_short_name_interactive <- function(team_name, existing_short_names = NULL) {
  # Interactive prompt for team short name
  # Validates uniqueness and format
  
  # Generate suggested short name
  suggested_short <- get_team_short_name(team_name)
  
  while (TRUE) {
    if (check_interactive_mode()) {
      cat("Enter 3-character short name for", team_name, "\n")
      cat("Suggested:", suggested_short, "\n")
      
      short_name <- get_user_input("Short name (press Enter for suggestion): ", default = suggested_short)
      
      if (trimws(short_name) == "") {
        short_name <- suggested_short
      }
    } else {
      # Non-interactive mode, use suggestion
      short_name <- suggested_short
      
      # Log the automatic decision
      log_file <- getOption("season_transition.log_file", NULL)
      if (!is.null(log_file)) {
        log_non_interactive_action(log_file, 
          paste("Auto-generated short name for", team_name),
          paste("Short name:", short_name))
      }
    }
    
    # Validate short name
    validation <- validate_team_short_name(short_name)
    if (!validation$valid) {
      cat("Invalid short name:", validation$message, "\n")
      if (!check_interactive_mode()) {
        # In non-interactive mode, generate a valid alternative
        short_name <- generate_valid_short_name(team_name, existing_short_names)
        break
      }
      next
    }
    
    # Check uniqueness
    if (!is.null(existing_short_names) && short_name %in% existing_short_names) {
      cat("Short name already exists. Please choose a different one.\n")
      if (!check_interactive_mode()) {
        # Generate unique alternative
        short_name <- generate_unique_short_name(short_name, existing_short_names)
        break
      }
      next
    }
    
    break
  }
  
  return(toupper(short_name))
}

get_initial_elo_interactive <- function(league, baseline = NULL) {
  # Interactive prompt for initial ELO
  # Provides league-appropriate defaults with optional baseline
  
  default_elo <- get_initial_elo_for_new_team(league, baseline)
  
  while (TRUE) {
    if (check_interactive_mode()) {
      cat("Enter initial ELO rating for", get_league_name(league), "\n")
      cat("Default:", default_elo, "\n")
      
      elo_input <- get_user_input("Initial ELO (press Enter for default): ", default = as.character(default_elo))
      
      if (trimws(elo_input) == "") {
        return(default_elo)
      }
      
      elo_value <- as.numeric(elo_input)
    } else {
      # Non-interactive mode, use default
      # Log the automatic decision
      log_file <- getOption("season_transition.log_file", NULL)
      if (!is.null(log_file)) {
        log_non_interactive_action(log_file, 
          paste("Auto-assigned default ELO for", get_league_name(league)),
          paste("ELO:", default_elo))
      }
      return(default_elo)
    }
    
    # Validate ELO
    validation <- validate_elo_input(elo_value)
    if (!validation$valid) {
      cat("Invalid ELO:", validation$message, "\n")
      next
    }
    
    return(elo_value)
  }
}

get_promotion_value_interactive <- function(team_name, league) {
  # Interactive prompt for promotion value
  # Handles Liga3 second teams automatically
  
  if (league != "80") {
    # Only Liga3 has promotion values
    return(0)
  }
  
  # Check if it's a second team
  if (detect_second_teams(team_name)) {
    if (check_interactive_mode()) {
      cat("Second team detected:", team_name, "\n")
      response <- get_user_input("Confirm this is a second team? (y/n): ", default = "y")
      if (tolower(trimws(response)) %in% c("y", "yes")) {
        cat("Setting promotion value to -50.\n")
        return(-50)
      }
    } else {
      cat("Second team detected. Setting promotion value to -50.\n")
      
      # Log the automatic decision
      log_file <- getOption("season_transition.log_file", NULL)
      if (!is.null(log_file)) {
        log_non_interactive_action(log_file, 
          paste("Auto-detected second team:", team_name),
          "Promotion value: -50")
      }
      
      return(-50)
    }
  }
  
  # For Liga3 first teams, promotion value is 0
  return(0)
}

confirm_overwrite <- function(file_path) {
  # Confirmation dialog for file overwrites
  # Returns TRUE if user confirms
  
  cat("\nFile already exists:", file_path, "\n")
  
  if (check_interactive_mode()) {
    response <- get_user_input("Overwrite existing file? (y/n): ", default = "n")
    return(tolower(trimws(response)) %in% c("y", "yes"))
  } else {
    cat("Running in non-interactive mode. Skipping overwrite.\n")
    return(FALSE)
  }
}

display_progress <- function(current_season, total_seasons, current_league = NULL) {
  # Progress indicator for multi-season processing
  # Shows current status and estimated completion
  
  season_progress <- (current_season - 1) / total_seasons * 100
  
  cat("\n=== Progress Update ===\n")
  cat("Season:", current_season, "of", total_seasons, "\n")
  cat("Progress:", sprintf("%.1f%%", season_progress), "\n")
  
  if (!is.null(current_league)) {
    cat("Current League:", get_league_name(current_league), "\n")
  }
  
  cat("=======================\n")
}

display_season_summary <- function(season, teams_processed, files_created) {
  # Display summary for completed season
  # Shows processing results
  
  cat("\n--- Season", season, "Summary ---\n")
  cat("Teams Processed:", teams_processed, "\n")
  cat("Files Created:", length(files_created), "\n")
  
  if (length(files_created) > 0) {
    cat("Files:\n")
    for (file in files_created) {
      cat("  -", file, "\n")
    }
  }
  
  cat("Status: Complete\n")
  cat("----------------------------\n")
}

prompt_for_continuation <- function(message) {
  # Generic continuation prompt
  # Returns TRUE if user wants to continue
  
  cat(message, "\n")
  
  if (check_interactive_mode()) {
    response <- get_user_input("Continue? (y/n): ", default = "y")
    return(tolower(trimws(response)) %in% c("y", "yes"))
  } else {
    cat("Running in non-interactive mode. Continuing automatically.\n")
    return(TRUE)
  }
}

display_error_recovery_options <- function(error_msg, context = NULL) {
  # Display error recovery options
  # Returns user choice
  
  cat("\n!!! Error Occurred !!!\n")
  cat("Error:", error_msg, "\n")
  
  if (!is.null(context)) {
    cat("Context:", context, "\n")
  }
  
  if (check_interactive_mode()) {
    cat("\nRecovery Options:\n")
    cat("1. Retry operation\n")
    cat("2. Skip and continue\n")
    cat("3. Abort processing\n")
    
    choice <- get_user_input("Choose option (1-3): ", default = "3")
    
    return(switch(trimws(choice),
      "1" = "retry",
      "2" = "skip",
      "3" = "abort",
      "abort"  # Default to abort for invalid input
    ))
  } else {
    cat("Running in non-interactive mode. Aborting on error.\n")
    return("abort")
  }
}

validate_user_input <- function(input, input_type = "text") {
  # Validate user input based on type
  # Returns validation result
  
  if (is.null(input) || trimws(input) == "") {
    return(list(
      valid = FALSE,
      message = "Input cannot be empty"
    ))
  }
  
  if (input_type == "season") {
    if (!grepl("^[0-9]{4}$", input)) {
      return(list(
        valid = FALSE,
        message = "Season must be a 4-digit year"
      ))
    }
    
    year <- as.numeric(input)
    if (year < 2000 || year > 2030) {
      return(list(
        valid = FALSE,
        message = "Season must be between 2000 and 2030"
      ))
    }
  }
  
  return(list(
    valid = TRUE,
    message = "Input valid"
  ))
}

generate_valid_short_name <- function(team_name, existing_short_names = NULL) {
  # Generate a valid short name when automatic generation fails
  # Ensures uniqueness and format compliance
  
  # Start with basic generation
  base_short <- get_team_short_name(team_name)
  
  # Ensure 3 characters
  if (nchar(base_short) < 3) {
    base_short <- paste0(base_short, paste(rep("X", 3 - nchar(base_short)), collapse = ""))
  } else if (nchar(base_short) > 3) {
    base_short <- substr(base_short, 1, 3)
  }
  
  # Make unique if needed
  if (!is.null(existing_short_names) && base_short %in% existing_short_names) {
    base_short <- generate_unique_short_name(base_short, existing_short_names)
  }
  
  return(toupper(base_short))
}

generate_unique_short_name <- function(base_short, existing_short_names) {
  # Generate unique short name by appending numbers
  # Maintains 3-character format
  
  if (nchar(base_short) == 3) {
    # Try replacing last character with numbers
    base_prefix <- substr(base_short, 1, 2)
    
    for (i in 1:9) {
      candidate <- paste0(base_prefix, i)
      if (!candidate %in% existing_short_names) {
        return(candidate)
      }
    }
    
    # If that fails, try replacing last two characters
    base_prefix <- substr(base_short, 1, 1)
    
    for (i in 10:99) {
      candidate <- paste0(base_prefix, i)
      if (!candidate %in% existing_short_names) {
        return(candidate)
      }
    }
  }
  
  # Fallback: generate completely new short name
  for (i in 1:999) {
    candidate <- sprintf("T%02d", i)
    if (!candidate %in% existing_short_names) {
      return(candidate)
    }
  }
  
  # Ultimate fallback
  return("UNK")
}

display_welcome_message <- function(source_season, target_season) {
  # Display welcome message and overview
  # Sets expectations for the process
  
  total_seasons <- as.numeric(target_season) - as.numeric(source_season)
  
  cat("======================================\n")
  cat("   Automated Season Transition Tool   \n")
  cat("======================================\n")
  cat("\n")
  cat("Source Season:", source_season, "\n")
  cat("Target Season:", target_season, "\n")
  cat("Seasons to Process:", total_seasons, "\n")
  cat("\n")
  cat("This tool will:\n")
  cat("1. Validate season completeness\n")
  cat("2. Calculate final ELO ratings\n")
  cat("3. Fetch team data from API\n")
  cat("4. Generate new team lists\n")
  cat("5. Handle interactive prompts for new teams\n")
  cat("\n")
  cat("Please ensure you have:\n")
  cat("- Valid RAPIDAPI_KEY environment variable\n")
  cat("- Internet connection for API calls\n")
  cat("- Write permissions for file creation\n")
  cat("\n")
  cat("Press Ctrl+C to cancel at any time.\n")
  cat("======================================\n\n")
}

display_completion_message <- function(seasons_processed, files_created) {
  # Display completion message and summary
  # Shows final results
  
  cat("\n======================================\n")
  cat("   Season Transition Complete!        \n")
  cat("======================================\n")
  cat("\n")
  cat("Seasons Processed:", seasons_processed, "\n")
  cat("Files Created:", length(files_created), "\n")
  cat("\n")
  
  if (length(files_created) > 0) {
    cat("Generated Files:\n")
    for (file in files_created) {
      cat("  ✓", file, "\n")
    }
  }
  
  cat("\n")
  cat("All team lists have been successfully generated.\n")
  cat("You can now use these files for league simulation.\n")
  cat("======================================\n")
}