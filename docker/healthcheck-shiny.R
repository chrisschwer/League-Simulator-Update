#!/usr/bin/env Rscript
# Health check script for Shiny updater container

tryCatch({
  # Check if required packages can be loaded
  suppressPackageStartupMessages({
    library(shiny)
    library(rsconnect)
    library(ggplot2)
  })
  
  # Check if directories are accessible
  if (!dir.exists("/ShinyApp/data")) {
    stop("ShinyApp data directory not accessible")
  }
  
  if (!dir.exists("/RCode/league_results")) {
    stop("League results directory not accessible")
  }
  
  cat("HEALTHY\n")
  quit(status = 0)
}, error = function(e) {
  cat("UNHEALTHY:", conditionMessage(e), "\n")
  quit(status = 1)
})