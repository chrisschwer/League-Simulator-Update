#!/usr/bin/env Rscript

# Diagnose why fixtures show as not finished
# Focus on understanding the fixture status structure

library(httr)
library(jsonlite)

# Color output
green <- function(text) paste0("\033[32m", text, "\033[0m")
red <- function(text) paste0("\033[31m", text, "\033[0m")
yellow <- function(text) paste0("\033[33m", text, "\033[0m")
blue <- function(text) paste0("\033[34m", text, "\033[0m")

cat(blue("=== Fixture Status Diagnostic ===\n\n"))

# Check API key
RAPIDAPI_KEY <- Sys.getenv("RAPIDAPI_KEY")
if (nchar(RAPIDAPI_KEY) == 0) {
  stop("RAPIDAPI_KEY not set!")
}

# Test with Bundesliga 2023 season
cat("Testing Bundesliga 2023 fixtures...\n\n")

url <- "https://api-football-v1.p.rapidapi.com/v3/fixtures"
response <- VERB("GET", url, 
  query = list(league = "78", season = "2023"),
  add_headers(
    'X-RapidAPI-Key' = RAPIDAPI_KEY,
    'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
  ),
  content_type("application/octet-stream")
)

if (status_code(response) == 200) {
  content_text <- content(response, "text", encoding = "UTF-8")
  parsed <- fromJSON(content_text)
  
  if (!is.null(parsed$response) && length(parsed$response) > 0) {
    fixtures <- parsed$response
    cat("Total fixtures found:", nrow(fixtures), "\n\n")
    
    # Analyze fixture structure
    cat("Sample fixture structure:\n")
    if (nrow(fixtures) > 0) {
      # Take first fixture
      first_fixture <- fixtures[1,]
      
      # Show fixture date and status
      cat("Fixture 1:\n")
      cat("  Date:", first_fixture$fixture$date, "\n")
      cat("  Status:", first_fixture$fixture$status$short, "\n")
      cat("  Status Long:", first_fixture$fixture$status$long, "\n")
      cat("  Elapsed:", first_fixture$fixture$status$elapsed, "\n")
      
      # Show teams
      cat("  Home:", first_fixture$teams$home$name, "\n")
      cat("  Away:", first_fixture$teams$away$name, "\n")
      
      # Show goals
      cat("  Score:", first_fixture$goals$home, "-", first_fixture$goals$away, "\n")
      
      cat("\n")
    }
    
    # Count different statuses
    cat("Status distribution:\n")
    status_counts <- table(fixtures$fixture$status$short)
    for (status in names(status_counts)) {
      cat("  ", status, ":", status_counts[status], "\n")
    }
    
    # Find finished matches using different approaches
    cat("\nDifferent ways to identify finished matches:\n")
    
    # Method 1: status.short == "FT"
    method1 <- sum(fixtures$fixture$status$short == "FT", na.rm = TRUE)
    cat("  Method 1 (status.short == 'FT'):", method1, "\n")
    
    # Method 2: status.long contains "Match Finished"
    method2 <- sum(grepl("Finished", fixtures$fixture$status$long, ignore.case = TRUE), na.rm = TRUE)
    cat("  Method 2 (status.long contains 'Finished'):", method2, "\n")
    
    # Method 3: elapsed == 90
    method3 <- sum(fixtures$fixture$status$elapsed == 90, na.rm = TRUE)
    cat("  Method 3 (elapsed == 90):", method3, "\n")
    
    # Method 4: goals are not NA
    method4 <- sum(!is.na(fixtures$goals$home) & !is.na(fixtures$goals$away), na.rm = TRUE)
    cat("  Method 4 (goals not NA):", method4, "\n")
    
    # Show some finished matches if found
    if (method1 > 0) {
      cat("\nSample finished matches (FT status):\n")
      ft_matches <- fixtures[fixtures$fixture$status$short == "FT", ]
      for (i in 1:min(3, nrow(ft_matches))) {
        m <- ft_matches[i,]
        cat(sprintf("  %s: %s %d - %d %s\n", 
          substr(m$fixture$date, 1, 10),
          m$teams$home$name, 
          m$goals$home,
          m$goals$away,
          m$teams$away$name
        ))
      }
    }
    
    # Debug: Show all unique status values
    cat("\nAll unique status.short values:\n")
    unique_statuses <- unique(fixtures$fixture$status$short)
    print(unique_statuses)
    
    # Save raw response for inspection
    cat("\nSaving raw response to fixtures_debug.json...\n")
    write(toJSON(fixtures[1:5,], pretty = TRUE), "fixtures_debug.json")
    
  } else {
    cat(red("No fixtures in response\n"))
  }
} else {
  cat(red("API request failed with status:"), status_code(response), "\n")
}

# Now test the retrieveResults function
cat("\n", blue("=== Testing retrieveResults Function ===\n\n"))

if (file.exists("RCode/retrieveResults.R")) {
  source("RCode/retrieveResults.R")
  
  cat("Testing retrieveResults for Bundesliga 2023...\n")
  results <- retrieveResults("78", "2023")
  
  if (!is.null(results) && nrow(results) > 0) {
    cat("Results retrieved:", nrow(results), "rows\n")
    
    # Check column names
    cat("\nColumn names:\n")
    print(names(results))
    
    # Check for fixture.status.short column
    if ("fixture.status.short" %in% names(results)) {
      cat("\nStatus distribution in retrieveResults:\n")
      print(table(results$fixture.status.short))
    } else if ("fixture_status_short" %in% names(results)) {
      cat("\nStatus distribution in retrieveResults:\n")
      print(table(results$fixture_status_short))
    } else {
      cat(yellow("\nWarning: No status column found\n"))
      cat("Available columns with 'status':\n")
      print(grep("status", names(results), value = TRUE, ignore.case = TRUE))
    }
    
  } else {
    cat(red("retrieveResults returned no data\n"))
  }
} else {
  cat(yellow("retrieveResults.R not found\n"))
}

cat("\n", green("Diagnostic complete!\n"))