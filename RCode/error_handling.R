# Error Handling Utilities
# Centralized error handling and recovery mechanisms

handle_processing_error <- function(error, context) {
  # Centralized error handling
  # Provides context and recovery suggestions
  
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  error_info <- list(
    timestamp = timestamp,
    error_message = conditionMessage(error),
    error_class = class(error),
    context = context,
    call_stack = sys.calls()
  )
  
  # Log error
  log_error(error_info)
  
  # Categorize error type
  error_type <- categorize_error(error)
  
  # Generate recovery suggestions
  recovery_suggestions <- generate_recovery_suggestions(error_type, context)
  
  # Display error information
  cat("\n!!! ERROR OCCURRED !!!\n")
  cat("Time:", timestamp, "\n")
  cat("Context:", context, "\n")
  cat("Error:", conditionMessage(error), "\n")
  cat("Type:", error_type, "\n")
  
  if (length(recovery_suggestions) > 0) {
    cat("\nRecovery Suggestions:\n")
    for (i in seq_along(recovery_suggestions)) {
      cat(paste0(i, ". ", recovery_suggestions[i], "\n"))
    }
  }
  
  return(list(
    error_info = error_info,
    error_type = error_type,
    recovery_suggestions = recovery_suggestions
  ))
}

categorize_error <- function(error) {
  # Categorize error type for appropriate handling
  # Returns error category
  
  error_message <- conditionMessage(error)
  
  # Network/API errors
  if (grepl("API|HTTP|network|connection|timeout", error_message, ignore.case = TRUE)) {
    return("network")
  }
  
  # File system errors
  if (grepl("file|directory|permission|disk|space", error_message, ignore.case = TRUE)) {
    return("filesystem")
  }
  
  # Data validation errors
  if (grepl("validation|invalid|format|missing|duplicate", error_message, ignore.case = TRUE)) {
    return("validation")
  }
  
  # Authentication errors
  if (grepl("unauthorized|authentication|key|token", error_message, ignore.case = TRUE)) {
    return("authentication")
  }
  
  # Rate limiting errors
  if (grepl("rate limit|quota|too many", error_message, ignore.case = TRUE)) {
    return("rate_limit")
  }
  
  # Memory/resource errors
  if (grepl("memory|resource|allocation", error_message, ignore.case = TRUE)) {
    return("resource")
  }
  
  # User input errors
  if (grepl("user|input|interactive", error_message, ignore.case = TRUE)) {
    return("user_input")
  }
  
  # Default category
  return("general")
}

generate_recovery_suggestions <- function(error_type, context) {
  # Generate context-specific recovery suggestions
  # Returns list of suggestions
  
  suggestions <- c()
  
  if (error_type == "network") {
    suggestions <- c(
      "Check internet connection",
      "Verify API endpoint availability",
      "Check firewall settings",
      "Retry operation after brief delay",
      "Check API service status"
    )
  } else if (error_type == "filesystem") {
    suggestions <- c(
      "Check file permissions",
      "Verify disk space availability",
      "Check if directory exists",
      "Ensure write permissions for output directory",
      "Check file locks by other processes"
    )
  } else if (error_type == "validation") {
    suggestions <- c(
      "Check input data format",
      "Verify required fields are present",
      "Check for duplicate entries",
      "Validate data types",
      "Review data constraints"
    )
  } else if (error_type == "authentication") {
    suggestions <- c(
      "Check RAPIDAPI_KEY environment variable",
      "Verify API key is valid and active",
      "Check API subscription status",
      "Ensure correct API endpoint",
      "Check API key permissions"
    )
  } else if (error_type == "rate_limit") {
    suggestions <- c(
      "Wait before retrying operation",
      "Check API quota usage",
      "Reduce request frequency",
      "Implement exponential backoff",
      "Contact API provider for quota increase"
    )
  } else if (error_type == "resource") {
    suggestions <- c(
      "Close unnecessary applications",
      "Reduce data processing batch size",
      "Check available memory",
      "Optimize data structures",
      "Consider processing in chunks"
    )
  } else if (error_type == "user_input") {
    suggestions <- c(
      "Check input format requirements",
      "Verify all required inputs provided",
      "Check for special characters",
      "Ensure interactive mode is available",
      "Use default values if available"
    )
  } else {
    suggestions <- c(
      "Check system requirements",
      "Verify all dependencies installed",
      "Review error logs for details",
      "Restart operation from beginning",
      "Contact support if problem persists"
    )
  }
  
  return(suggestions)
}

log_error <- function(error_info) {
  # Log error to file for debugging
  # Creates structured error log
  
  tryCatch({
    error_log_file <- "error_log.json"
    
    # Create log entry
    log_entry <- list(
      timestamp = error_info$timestamp,
      error_message = error_info$error_message,
      error_class = error_info$error_class,
      context = error_info$context,
      session_info = list(
        r_version = R.version.string,
        platform = R.version$platform,
        working_directory = getwd(),
        environment_variables = list(
          RAPIDAPI_KEY = ifelse(Sys.getenv("RAPIDAPI_KEY") != "", "SET", "NOT_SET")
        )
      )
    )
    
    # Write to log file
    if (file.exists(error_log_file)) {
      # Append to existing log
      existing_log <- readLines(error_log_file)
      new_log <- c(existing_log, jsonlite::toJSON(log_entry, auto_unbox = TRUE))
      writeLines(new_log, error_log_file)
    } else {
      # Create new log
      writeLines(jsonlite::toJSON(log_entry, auto_unbox = TRUE), error_log_file)
    }
    
  }, error = function(e) {
    # Fallback - print to console if logging fails
    cat("Error logging failed:", conditionMessage(e), "\n")
    cat("Original error:", error_info$error_message, "\n")
  })
}

create_error_report <- function(errors, session_context) {
  # Generate comprehensive error report
  # Returns formatted report
  
  tryCatch({
    if (length(errors) == 0) {
      return(NULL)
    }
    
    # Analyze error patterns
    error_types <- sapply(errors, function(e) categorize_error(e))
    error_summary <- table(error_types)
    
    # Create report
    report <- list(
      timestamp = Sys.time(),
      session_context = session_context,
      total_errors = length(errors),
      error_types = error_summary,
      errors = errors
    )
    
    # Generate report file
    report_file <- paste0("error_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json")
    writeLines(jsonlite::toJSON(report, pretty = TRUE), report_file)
    
    # Print summary
    cat("\n=== Error Report Summary ===\n")
    cat("Total Errors:", length(errors), "\n")
    cat("Error Types:\n")
    for (type in names(error_summary)) {
      cat("  ", type, ":", error_summary[type], "\n")
    }
    cat("Report saved to:", report_file, "\n")
    cat("============================\n")
    
    return(report)
    
  }, error = function(e) {
    warning("Error creating error report:", conditionMessage(e))
    return(NULL)
  })
}

handle_network_error <- function(error, operation = "API call") {
  # Handle network-specific errors
  # Returns retry recommendation
  
  error_message <- conditionMessage(error)
  
  # Check for specific network error types
  if (grepl("timeout", error_message, ignore.case = TRUE)) {
    return(list(
      action = "retry",
      delay = 5,
      message = "Network timeout - retrying with increased delay"
    ))
  } else if (grepl("connection refused", error_message, ignore.case = TRUE)) {
    return(list(
      action = "abort",
      message = "Connection refused - service may be down"
    ))
  } else if (grepl("host not found", error_message, ignore.case = TRUE)) {
    return(list(
      action = "abort",
      message = "Host not found - check network connectivity"
    ))
  } else if (grepl("SSL", error_message, ignore.case = TRUE)) {
    return(list(
      action = "retry",
      delay = 2,
      message = "SSL error - retrying with brief delay"
    ))
  } else {
    return(list(
      action = "retry",
      delay = 3,
      message = "General network error - retrying"
    ))
  }
}

handle_file_error <- function(error, operation = "file operation") {
  # Handle file system errors
  # Returns recovery action
  
  error_message <- conditionMessage(error)
  
  if (grepl("permission denied", error_message, ignore.case = TRUE)) {
    return(list(
      action = "abort",
      message = "Permission denied - check file permissions"
    ))
  } else if (grepl("no space", error_message, ignore.case = TRUE)) {
    return(list(
      action = "abort",
      message = "No disk space - free up space and retry"
    ))
  } else if (grepl("file not found", error_message, ignore.case = TRUE)) {
    return(list(
      action = "recover",
      message = "File not found - attempting to create"
    ))
  } else if (grepl("file exists", error_message, ignore.case = TRUE)) {
    return(list(
      action = "prompt",
      message = "File exists - prompt for overwrite"
    ))
  } else {
    return(list(
      action = "retry",
      delay = 1,
      message = "File system error - retrying"
    ))
  }
}

create_recovery_checkpoint <- function(context, data = NULL) {
  # Create recovery checkpoint for rollback
  # Returns checkpoint identifier
  
  tryCatch({
    checkpoint_id <- paste0("checkpoint_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    checkpoint_file <- paste0(checkpoint_id, ".rds")
    
    checkpoint_data <- list(
      timestamp = Sys.time(),
      context = context,
      data = data,
      working_directory = getwd(),
      session_info = sessionInfo()
    )
    
    saveRDS(checkpoint_data, checkpoint_file)
    
    cat("Recovery checkpoint created:", checkpoint_file, "\n")
    
    return(checkpoint_id)
    
  }, error = function(e) {
    warning("Failed to create recovery checkpoint:", conditionMessage(e))
    return(NULL)
  })
}

restore_from_checkpoint <- function(checkpoint_id) {
  # Restore from recovery checkpoint
  # Returns restored data or NULL
  
  tryCatch({
    checkpoint_file <- paste0(checkpoint_id, ".rds")
    
    if (!file.exists(checkpoint_file)) {
      warning("Checkpoint file not found:", checkpoint_file)
      return(NULL)
    }
    
    checkpoint_data <- readRDS(checkpoint_file)
    
    cat("Restored from checkpoint:", checkpoint_file, "\n")
    cat("Checkpoint context:", checkpoint_data$context, "\n")
    cat("Checkpoint time:", checkpoint_data$timestamp, "\n")
    
    return(checkpoint_data)
    
  }, error = function(e) {
    warning("Failed to restore from checkpoint:", conditionMessage(e))
    return(NULL)
  })
}

cleanup_checkpoints <- function(max_age_hours = 24) {
  # Clean up old recovery checkpoints
  # Returns number of checkpoints removed
  
  tryCatch({
    checkpoint_files <- list.files(pattern = "^checkpoint_.*\\.rds$")
    
    if (length(checkpoint_files) == 0) {
      return(0)
    }
    
    cutoff_time <- Sys.time() - (max_age_hours * 3600)
    removed_count <- 0
    
    for (file in checkpoint_files) {
      if (file.info(file)$mtime < cutoff_time) {
        file.remove(file)
        removed_count <- removed_count + 1
      }
    }
    
    if (removed_count > 0) {
      cat("Removed", removed_count, "old recovery checkpoints\n")
    }
    
    return(removed_count)
    
  }, error = function(e) {
    warning("Error cleaning up checkpoints:", conditionMessage(e))
    return(0)
  })
}

validate_system_requirements <- function() {
  # Validate system requirements and dependencies
  # Returns validation results
  
  tryCatch({
    requirements <- list(
      r_version = list(
        required = "4.0.0",
        actual = R.version.string,
        valid = as.numeric(R.version$major) >= 4
      ),
      packages = list(),
      environment = list(),
      system = list()
    )
    
    # Check required packages
    required_packages <- c("httr", "jsonlite", "tidyr")
    
    for (pkg in required_packages) {
      requirements$packages[[pkg]] <- list(
        required = TRUE,
        installed = requireNamespace(pkg, quietly = TRUE)
      )
    }
    
    # Check environment variables
    requirements$environment$RAPIDAPI_KEY <- list(
      required = TRUE,
      set = Sys.getenv("RAPIDAPI_KEY") != ""
    )
    
    # Check system resources
    requirements$system$disk_space <- list(
      required = "1GB",
      available = get_available_disk_space() > 1e9
    )
    
    # Overall validation
    all_valid <- all(
      requirements$r_version$valid,
      all(sapply(requirements$packages, function(p) p$installed)),
      all(sapply(requirements$environment, function(e) e$set)),
      all(sapply(requirements$system, function(s) s$available))
    )
    
    requirements$overall_valid <- all_valid
    
    return(requirements)
    
  }, error = function(e) {
    return(list(
      overall_valid = FALSE,
      error = conditionMessage(e)
    ))
  })
}