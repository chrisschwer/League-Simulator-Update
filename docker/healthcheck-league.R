#!/usr/bin/env Rscript
# Health check script for league updater container

tryCatch({
  # Check if required packages can be loaded
  suppressPackageStartupMessages({
    library(httr)
    library(jsonlite)
    library(dplyr)
  })
  
  # Check if results directory is writable
  test_file <- "/RCode/league_results/.healthcheck"
  writeLines("OK", test_file)
  
  if (file.exists(test_file)) {
    unlink(test_file)
    cat("HEALTHY\n")
    quit(status = 0)
  } else {
    cat("UNHEALTHY: Cannot write to results directory\n")
    quit(status = 1)
  }
}, error = function(e) {
  cat("UNHEALTHY:", conditionMessage(e), "\n")
  quit(status = 1)
})