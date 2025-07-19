# Test Helper Infrastructure
# This file is automatically loaded before any tests are run
# It ensures all necessary components are available for testing

# Load required packages
suppressPackageStartupMessages({
  library(testthat)
  library(Rcpp)
  library(data.table)
  library(dplyr)
  library(readr)
  library(httr)
  library(jsonlite)
  library(stringr)
  library(lubridate)
})

# Set consistent locale for tests to avoid locale-dependent failures
Sys.setlocale("LC_TIME", "C")
Sys.setlocale("LC_NUMERIC", "C")
Sys.setlocale("LC_COLLATE", "C")

# Define base paths
# When running tests, the working directory should be the project root
BASE_PATH <- getwd()
if (!file.exists(file.path(BASE_PATH, "RCode"))) {
  # Try to find the project root
  possible_paths <- c(
    normalizePath("../.."),
    normalizePath("."),
    dirname(dirname(getwd()))
  )
  for (path in possible_paths) {
    if (file.exists(file.path(path, "RCode"))) {
      BASE_PATH <- path
      break
    }
  }
}
RCODE_PATH <- file.path(BASE_PATH, "RCode")
SRC_PATH <- file.path(BASE_PATH, "src")

# Source all R modules from RCode directory
source_rcode_modules <- function() {
  r_files <- list.files(
    RCODE_PATH, 
    pattern = "\\.R$", 
    full.names = TRUE,
    recursive = FALSE
  )
  
  # Exclude certain files that might cause issues during testing
  exclude_patterns <- c(
    "updateScheduler\\.R",
    "update_all_leagues_loop\\.R",
    "run_single_update"
  )
  
  for (pattern in exclude_patterns) {
    r_files <- r_files[!grepl(pattern, basename(r_files))]
  }
  
  # Source files in a specific order to handle dependencies
  priority_files <- c(
    "api_service.R",
    "season_validation.R",
    "interactive_prompts.R",
    "csv_generation.R",
    "transform_data.R",
    "input_handler.R",
    "elo_calculations.R",
    "Tabelle.R"
  )
  
  # Source priority files first
  for (file in priority_files) {
    file_path <- file.path(RCODE_PATH, file)
    if (file.exists(file_path)) {
      tryCatch(
        source(file_path),
        error = function(e) {
          message("Warning: Could not source ", file, ": ", e$message)
        }
      )
    }
  }
  
  # Source remaining files
  for (file in r_files) {
    if (!basename(file) %in% priority_files) {
      tryCatch(
        source(file),
        error = function(e) {
          message("Warning: Could not source ", basename(file), ": ", e$message)
        }
      )
    }
  }
}

# Compile C++ files
compile_cpp_files <- function() {
  # Look for C++ files in both src and RCode directories
  cpp_paths <- c(
    SRC_PATH,
    RCODE_PATH
  )
  
  cpp_files <- character()
  for (path in cpp_paths) {
    if (dir.exists(path)) {
      files <- list.files(
        path,
        pattern = "\\.cpp$",
        full.names = TRUE
      )
      cpp_files <- c(cpp_files, files)
    }
  }
  
  # Specifically compile SpielNichtSimulieren.cpp first as it's a dependency
  spiel_cpp <- file.path(RCODE_PATH, "SpielNichtSimulieren.cpp")
  if (file.exists(spiel_cpp)) {
    tryCatch({
      message("Compiling: SpielNichtSimulieren.cpp")
      Rcpp::sourceCpp(spiel_cpp, rebuild = TRUE)
    }, error = function(e) {
      message("Warning: Could not compile SpielNichtSimulieren.cpp: ", e$message)
    })
  }
  
  # Compile other C++ files
  for (cpp_file in cpp_files) {
    if (basename(cpp_file) != "SpielNichtSimulieren.cpp") {
      tryCatch({
        message("Compiling: ", basename(cpp_file))
        Rcpp::sourceCpp(cpp_file, rebuild = TRUE)
      }, error = function(e) {
        message("Warning: Could not compile ", basename(cpp_file), ": ", e$message)
      })
    }
  }
}

# Helper function to create test data directories
setup_test_directories <- function() {
  test_dirs <- c(
    "tests/testthat/fixtures/test-data",
    "tests/testthat/fixtures/api-responses",
    "tests/testthat/temp"
  )
  
  for (dir in test_dirs) {
    dir_path <- file.path(BASE_PATH, dir)
    if (!dir.exists(dir_path)) {
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
    }
  }
}

# Helper function to clean up temporary test files
cleanup_test_files <- function() {
  temp_dir <- file.path(BASE_PATH, "tests/testthat/temp")
  if (dir.exists(temp_dir)) {
    unlink(temp_dir, recursive = TRUE)
    dir.create(temp_dir, showWarnings = FALSE)
  }
}

# Execute setup
tryCatch({
  message("Setting up test environment...")
  setup_test_directories()
  source_rcode_modules()
  compile_cpp_files()
  message("Test environment setup complete")
}, error = function(e) {
  message("Error during test setup: ", e$message)
})

# Register cleanup hook (skip if not in test environment)
tryCatch({
  if (exists(".test_env", where = asNamespace("testthat"))) {
    withr::defer(cleanup_test_files(), envir = get(".test_env", envir = asNamespace("testthat")))
  }
}, error = function(e) {
  # Not in test environment, skip cleanup registration
})

# Export useful test helpers
test_team_data <- function() {
  data.frame(
    Team_ID = c(168, 169, 170),
    Team_Name = c("Bayern Munich", "Borussia Dortmund", "RB Leipzig"),
    ShortName = c("FCB", "BVB", "RBL"),
    Liga = c(1, 1, 1),
    ELO_aktuell = c(1850, 1780, 1720),
    stringsAsFactors = FALSE
  )
}

test_match_data <- function() {
  data.frame(
    Heim = c(168, 169, 170),
    Auswaerts = c(169, 170, 168),
    Ergebnis = c("2:1", "1:1", "0:2"),
    stringsAsFactors = FALSE
  )
}