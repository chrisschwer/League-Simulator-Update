# Logging Functionality
# Structured logging for debugging and monitoring

create_non_interactive_log <- function(from_season, to_season) {
  # Create detailed log file for non-interactive runs
  # Returns log file path

  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  log_filename <- paste0("season_transition_", from_season, "_",
                         to_season, "_", timestamp, ".log")
  log_filepath <- file.path("logs", log_filename)

  # Create logs directory if it doesn't exist
  if (!dir.exists("logs")) {
    dir.create("logs")
  }

  # Initialize log file
  cat("=== Season Transition Log ===\n", file = log_filepath)
  cat("Mode: Non-Interactive\n", file = log_filepath, append = TRUE)
  cat("From Season:", from_season, "\n", file = log_filepath, append = TRUE)
  cat("To Season:", to_season, "\n", file = log_filepath, append = TRUE)
  cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n",
      file = log_filepath, append = TRUE)

  return(log_filepath)
}

log_non_interactive_action <- function(log_file, action, details = NULL) {
  # Log actions taken in non-interactive mode

  if (!file.exists(log_file)) {
    return()
  }

  timestamp <- format(Sys.time(), "%H:%M:%S")
  log_entry <- paste0("[", timestamp, "] ", action)

  if (!is.null(details)) {
    log_entry <- paste0(log_entry, "\n  Details: ", details)
  }

  cat(log_entry, "\n", file = log_file, append = TRUE)
}

# Global logging configuration
.LOG_CONFIG <- list(
  level = "INFO",
  file = "season_transition.log",
  console = TRUE,
  max_size = 10 * 1024 * 1024,  # 10MB
  max_files = 5
)

LOG_LEVELS <- list(
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
  FATAL = 5
)

log_message <- function(level, message, context = NULL) {
  # Structured logging for debugging
  # Different log levels (DEBUG, INFO, WARN, ERROR, FATAL)
  
  tryCatch({
    # Check if level is valid
    if (!level %in% names(LOG_LEVELS)) {
      level <- "INFO"
    }
    
    # Check if message should be logged based on level
    if (LOG_LEVELS[[level]] < LOG_LEVELS[[.LOG_CONFIG$level]]) {
      return()
    }
    
    # Create log entry
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    
    log_entry <- list(
      timestamp = timestamp,
      level = level,
      message = message,
      context = context,
      pid = Sys.getpid(),
      session_id = get_session_id()
    )
    
    # Format log message
    formatted_message <- format_log_message(log_entry)
    
    # Write to console if enabled
    if (.LOG_CONFIG$console) {
      cat(formatted_message, "\n")
    }
    
    # Write to file
    write_log_to_file(log_entry, formatted_message)
    
  }, error = function(e) {
    # Fallback - write to console if logging fails
    cat("LOGGING ERROR:", conditionMessage(e), "\n")
    cat("Original message:", message, "\n")
  })
}

format_log_message <- function(log_entry) {
  # Format log message for output
  # Returns formatted string
  
  formatted <- paste0(
    "[", log_entry$timestamp, "] ",
    "[", log_entry$level, "] ",
    log_entry$message
  )
  
  if (!is.null(log_entry$context)) {
    formatted <- paste0(formatted, " (", log_entry$context, ")")
  }
  
  return(formatted)
}

write_log_to_file <- function(log_entry, formatted_message) {
  # Write log entry to file
  # Handles file rotation and size limits
  
  tryCatch({
    log_file <- .LOG_CONFIG$file
    
    # Check if log rotation is needed
    if (file.exists(log_file)) {
      file_size <- file.info(log_file)$size
      
      if (file_size > .LOG_CONFIG$max_size) {
        rotate_log_files()
      }
    }
    
    # Write to log file
    write(formatted_message, log_file, append = TRUE)
    
  }, error = function(e) {
    # Fallback - write to console if file writing fails
    cat("LOG FILE ERROR:", conditionMessage(e), "\n")
    cat(formatted_message, "\n")
  })
}

rotate_log_files <- function() {
  # Rotate log files when size limit is reached
  # Keeps specified number of historical files
  
  tryCatch({
    log_file <- .LOG_CONFIG$file
    max_files <- .LOG_CONFIG$max_files
    
    if (!file.exists(log_file)) {
      return()
    }
    
    # Rotate existing files
    for (i in (max_files - 1):1) {
      old_file <- paste0(log_file, ".", i)
      new_file <- paste0(log_file, ".", i + 1)
      
      if (file.exists(old_file)) {
        file.rename(old_file, new_file)
      }
    }
    
    # Move current log to .1
    file.rename(log_file, paste0(log_file, ".1"))
    
    cat("Log files rotated\n")
    
  }, error = function(e) {
    warning("Log rotation failed:", conditionMessage(e))
  })
}

get_session_id <- function() {
  # Get or create session ID for tracking
  # Returns session identifier
  
  if (!exists(".SESSION_ID", envir = .GlobalEnv)) {
    session_id <- paste0("session_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    assign(".SESSION_ID", session_id, envir = .GlobalEnv)
  }
  
  return(get(".SESSION_ID", envir = .GlobalEnv))
}

create_processing_log <- function(source_season, target_season) {
  # Create processing log file
  # Tracks all operations and decisions
  
  tryCatch({
    log_file <- paste0("processing_", source_season, "_to_", target_season, ".log")
    
    # Set processing-specific log file
    old_log_file <- .LOG_CONFIG$file
    .LOG_CONFIG$file <<- log_file
    
    # Log processing start
    log_message("INFO", "Processing started", paste("Source:", source_season, "Target:", target_season))
    
    # Log system information
    log_message("DEBUG", "System information", paste("R version:", R.version.string))
    log_message("DEBUG", "Working directory", getwd())
    log_message("DEBUG", "Session ID", get_session_id())
    
    return(log_file)
    
  }, error = function(e) {
    warning("Failed to create processing log:", conditionMessage(e))
    return(NULL)
  })
}

log_api_call <- function(endpoint, params = NULL, success = TRUE, response_size = NULL) {
  # Log API call details
  # Tracks API usage and performance
  
  context <- paste("API:", endpoint)
  
  if (success) {
    message <- "API call successful"
    level <- "INFO"
  } else {
    message <- "API call failed"
    level <- "ERROR"
  }
  
  if (!is.null(params)) {
    message <- paste(message, "- Params:", jsonlite::toJSON(params, auto_unbox = TRUE))
  }
  
  if (!is.null(response_size)) {
    message <- paste(message, "- Response size:", response_size, "bytes")
  }
  
  log_message(level, message, context)
}

log_file_operation <- function(operation, file_path, success = TRUE, details = NULL) {
  # Log file operations
  # Tracks file system interactions
  
  context <- paste("File:", operation)
  
  if (success) {
    message <- paste(operation, "successful:", file_path)
    level <- "INFO"
  } else {
    message <- paste(operation, "failed:", file_path)
    level <- "ERROR"
  }
  
  if (!is.null(details)) {
    message <- paste(message, "-", details)
  }
  
  log_message(level, message, context)
}

log_team_processing <- function(team_name, team_id, league, action, elo = NULL) {
  # Log team processing details
  # Tracks team-specific operations
  
  context <- paste("Team:", team_name)
  
  message <- paste("Team", action, "in", get_league_name(league))
  
  if (!is.null(elo)) {
    message <- paste(message, "- ELO:", elo)
  }
  
  log_message("INFO", message, context)
}

log_validation_result <- function(validation_type, result, details = NULL) {
  # Log validation results
  # Tracks data quality and integrity
  
  context <- paste("Validation:", validation_type)
  
  if (result$valid) {
    message <- paste(validation_type, "validation passed")
    level <- "INFO"
  } else {
    message <- paste(validation_type, "validation failed:", result$message)
    level <- "WARN"
  }
  
  if (!is.null(details)) {
    message <- paste(message, "-", details)
  }
  
  log_message(level, message, context)
}

log_user_interaction <- function(prompt_type, response, team_name = NULL) {
  # Log user interactions
  # Tracks user input and decisions
  
  context <- "User Interaction"
  
  if (!is.null(team_name)) {
    context <- paste(context, "- Team:", team_name)
  }
  
  message <- paste("User", prompt_type, "- Response:", response)
  
  log_message("INFO", message, context)
}

log_performance_metric <- function(operation, duration, details = NULL) {
  # Log performance metrics
  # Tracks operation timing and efficiency
  
  context <- paste("Performance:", operation)
  
  message <- paste(operation, "completed in", round(duration, 2), "seconds")
  
  if (!is.null(details)) {
    message <- paste(message, "-", details)
  }
  
  log_message("INFO", message, context)
}

set_log_level <- function(level) {
  # Set minimum log level
  # Controls verbosity of logging
  
  if (level %in% names(LOG_LEVELS)) {
    .LOG_CONFIG$level <<- level
    log_message("INFO", paste("Log level set to", level))
  } else {
    warning("Invalid log level:", level)
  }
}

set_log_file <- function(file_path) {
  # Set log file path
  # Changes where log messages are written
  
  .LOG_CONFIG$file <<- file_path
  log_message("INFO", paste("Log file set to", file_path))
}

enable_console_logging <- function(enabled = TRUE) {
  # Enable or disable console logging
  # Controls whether messages appear in console
  
  .LOG_CONFIG$console <<- enabled
  
  if (enabled) {
    log_message("INFO", "Console logging enabled")
  } else {
    cat("Console logging disabled\n")
  }
}

get_log_summary <- function(log_file = NULL) {
  # Get summary of log entries
  # Returns log statistics
  
  if (is.null(log_file)) {
    log_file <- .LOG_CONFIG$file
  }
  
  tryCatch({
    if (!file.exists(log_file)) {
      return(list(
        error = "Log file not found"
      ))
    }
    
    # Read log file
    log_lines <- readLines(log_file)
    
    # Parse log levels
    levels <- regmatches(log_lines, regexpr("\\[(DEBUG|INFO|WARN|ERROR|FATAL)\\]", log_lines))
    levels <- gsub("\\[|\\]", "", levels)
    
    # Count by level
    level_counts <- table(levels)
    
    summary <- list(
      total_entries = length(log_lines),
      level_counts = level_counts,
      file_size = file.info(log_file)$size,
      last_modified = file.info(log_file)$mtime
    )
    
    return(summary)
    
  }, error = function(e) {
    return(list(
      error = conditionMessage(e)
    ))
  })
}

export_log_analysis <- function(log_file = NULL, output_file = NULL) {
  # Export log analysis to CSV
  # Creates structured analysis of log data
  
  if (is.null(log_file)) {
    log_file <- .LOG_CONFIG$file
  }
  
  if (is.null(output_file)) {
    output_file <- paste0("log_analysis_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")
  }
  
  tryCatch({
    if (!file.exists(log_file)) {
      warning("Log file not found:", log_file)
      return(NULL)
    }
    
    # Read and parse log file
    log_lines <- readLines(log_file)
    
    # Extract log components
    timestamps <- regmatches(log_lines, regexpr("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}", log_lines))
    levels <- regmatches(log_lines, regexpr("\\[(DEBUG|INFO|WARN|ERROR|FATAL)\\]", log_lines))
    levels <- gsub("\\[|\\]", "", levels)
    
    # Create analysis data frame
    analysis_data <- data.frame(
      timestamp = timestamps,
      level = levels,
      line_number = seq_along(log_lines),
      message_length = nchar(log_lines),
      stringsAsFactors = FALSE
    )
    
    # Write analysis to CSV
    write.csv(analysis_data, output_file, row.names = FALSE)
    
    cat("Log analysis exported to:", output_file, "\n")
    
    return(analysis_data)
    
  }, error = function(e) {
    warning("Error exporting log analysis:", conditionMessage(e))
    return(NULL)
  })
}

cleanup_old_logs <- function(max_age_days = 30) {
  # Clean up old log files
  # Removes logs older than specified age
  
  tryCatch({
    log_pattern <- "\\.(log|log\\.\\d+)$"
    log_files <- list.files(pattern = log_pattern, full.names = TRUE)
    
    if (length(log_files) == 0) {
      return(0)
    }
    
    cutoff_time <- Sys.time() - (max_age_days * 24 * 60 * 60)
    removed_count <- 0
    
    for (file in log_files) {
      if (file.info(file)$mtime < cutoff_time) {
        file.remove(file)
        removed_count <- removed_count + 1
      }
    }
    
    if (removed_count > 0) {
      log_message("INFO", paste("Cleaned up", removed_count, "old log files"))
    }
    
    return(removed_count)
    
  }, error = function(e) {
    warning("Error cleaning up old logs:", conditionMessage(e))
    return(0)
  })
}

# Convenience functions for common log levels
log_debug <- function(message, context = NULL) {
  log_message("DEBUG", message, context)
}

log_info <- function(message, context = NULL) {
  log_message("INFO", message, context)
}

log_warn <- function(message, context = NULL) {
  log_message("WARN", message, context)
}

log_error <- function(message, context = NULL) {
  log_message("ERROR", message, context)
}

log_fatal <- function(message, context = NULL) {
  log_message("FATAL", message, context)
}

