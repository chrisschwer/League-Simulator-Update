#!/usr/bin/env Rscript

# Automated Season Transition Script
# Creates team lists for intermediate seasons between source and target seasons
# Usage: Rscript season_transition.R <source_season> <target_season>

# Load required libraries
suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(tidyr)
})

# Source required modules
source_path <- function(file) {
  file.path(dirname(dirname(rstudioapi::getActiveDocumentContext()$path)), "RCode", file)
}

# Try to source files, with fallback for different execution contexts
safe_source <- function(file) {
  # Try relative path first
  rcode_path <- file.path("RCode", file)
  if (file.exists(rcode_path)) {
    source(rcode_path)
    return(TRUE)
  }
  
  # Try absolute path based on script location
  script_dir <- dirname(sys.frame(1)$ofile)
  if (!is.null(script_dir)) {
    abs_path <- file.path(dirname(script_dir), "RCode", file)
    if (file.exists(abs_path)) {
      source(abs_path)
      return(TRUE)
    }
  }
  
  # Try current working directory
  cwd_path <- file.path(getwd(), "RCode", file)
  if (file.exists(cwd_path)) {
    source(cwd_path)
    return(TRUE)
  }
  
  return(FALSE)
}

# Source required modules
required_modules <- c(
  "season_validation.R",
  "elo_aggregation.R",
  "api_service.R",
  "api_helpers.R",
  "interactive_prompts.R",
  "input_validation.R",
  "csv_generation.R",
  "file_operations.R",
  "season_processor.R",
  "league_processor.R",
  "error_handling.R",
  "logging.R"
)

# Source existing modules that we'll use
existing_modules <- c(
  "retrieveResults.R",
  "transform_data.R"
)

# Source all modules
cat("Loading required modules...\n")
for (module in required_modules) {
  if (!safe_source(module)) {
    warning(paste("Could not source required module:", module))
  }
}

for (module in existing_modules) {
  if (!safe_source(module)) {
    warning(paste("Could not source existing module:", module))
  }
}

main <- function(args) {
  # Validate command line arguments
  if (length(args) != 2) {
    cat("Usage: Rscript season_transition.R <source_season> <target_season>\n")
    cat("Example: Rscript season_transition.R 2023 2024\n")
    quit(status = 1)
  }
  
  source_season <- args[1]
  target_season <- args[2]
  
  # Basic validation
  if (!grepl("^[0-9]{4}$", source_season) || !grepl("^[0-9]{4}$", target_season)) {
    cat("Error: Seasons must be 4-digit years (e.g., 2023, 2024)\n")
    quit(status = 1)
  }
  
  if (as.numeric(source_season) >= as.numeric(target_season)) {
    cat("Error: Target season must be after source season\n")
    quit(status = 1)
  }
  
  # Check for API key
  if (Sys.getenv("RAPIDAPI_KEY") == "") {
    cat("Error: RAPIDAPI_KEY environment variable not set\n")
    cat("Please set your RapidAPI key: export RAPIDAPI_KEY=your_key_here\n")
    quit(status = 1)
  }
  
  cat("=== Automated Season Transition Script ===\n")
  cat("Source Season:", source_season, "\n")
  cat("Target Season:", target_season, "\n")
  cat("Processing", as.numeric(target_season) - as.numeric(source_season), "season(s)\n\n")
  
  # Start processing
  tryCatch({
    # Initialize logging
    log_file <- create_processing_log(source_season, target_season)
    
    # Validate system requirements
    system_check <- validate_system_requirements()
    if (!system_check$overall_valid) {
      stop("System requirements validation failed")
    }
    
    # Process season transition
    result <- process_season_transition(source_season, target_season)
    
    if (result$success) {
      cat("\n=== Season Transition Complete ===\n")
      cat("Seasons processed:", result$seasons_processed, "\n")
      cat("Files created:", length(result$files_created), "\n")
      cat("All team lists have been generated successfully.\n")
    } else {
      stop(paste("Season transition failed:", result$error))
    }
    
  }, error = function(e) {
    cat("Error during season transition:\n")
    cat(conditionMessage(e), "\n")
    
    # Log error
    log_error(conditionMessage(e), "main")
    
    quit(status = 1)
  })
}

# Main execution
if (!interactive()) {
  main(commandArgs(trailingOnly = TRUE))
}