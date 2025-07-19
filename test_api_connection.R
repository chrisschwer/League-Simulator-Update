#!/usr/bin/env Rscript

# API-Football Connection Test Script
# Tests all relevant endpoints for German leagues
# Usage: Rscript test_api_connection.R

library(httr)
library(jsonlite)

# Color output for better readability
green <- function(text) paste0("\033[32m", text, "\033[0m")
red <- function(text) paste0("\033[31m", text, "\033[0m")
yellow <- function(text) paste0("\033[33m", text, "\033[0m")
blue <- function(text) paste0("\033[34m", text, "\033[0m")

# League configuration
leagues <- list(
  list(id = "78", name = "Bundesliga"),
  list(id = "79", name = "2. Bundesliga"),
  list(id = "80", name = "3. Liga")
)

# Test seasons
test_seasons <- c("2023", "2024", "2025")

# Initialize results tracking
results <- list()

cat(blue("========================================\n"))
cat(blue("API-Football Connection Test\n"))
cat(blue("========================================\n\n"))

# Check API key
RAPIDAPI_KEY <- Sys.getenv("RAPIDAPI_KEY")
if (nchar(RAPIDAPI_KEY) == 0) {
  cat(red("ERROR: RAPIDAPI_KEY environment variable not set!\n"))
  cat("Please set it with: export RAPIDAPI_KEY='your_key_here'\n")
  quit(status = 1)
} else {
  cat(green("✓ API Key found"), "(length:", nchar(RAPIDAPI_KEY), "chars)\n\n")
}

# Base configuration
base_url <- "https://api-football-v1.p.rapidapi.com/v3"
headers <- add_headers(
  'X-RapidAPI-Key' = RAPIDAPI_KEY,
  'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
)

# Function to make API request
make_request <- function(endpoint, params = list()) {
  url <- paste0(base_url, endpoint)
  
  tryCatch({
    response <- VERB("GET", url, query = params, headers, content_type("application/octet-stream"))
    
    # Check status code
    status <- status_code(response)
    
    # Parse response
    content_text <- content(response, "text", encoding = "UTF-8")
    
    # Try to parse JSON
    parsed <- tryCatch({
      fromJSON(content_text)
    }, error = function(e) {
      list(error = paste("JSON parse error:", e$message))
    })
    
    return(list(
      status = status,
      content = parsed,
      raw = content_text
    ))
    
  }, error = function(e) {
    return(list(
      status = 0,
      error = e$message
    ))
  })
}

# Test 1: API Status
cat(yellow("1. Testing API Status Endpoint\n"))
cat("   Endpoint: /status\n")

status_response <- make_request("/status")

if (status_response$status == 200) {
  cat(green("   ✓ API is accessible\n"))
  
  if (!is.null(status_response$content$response)) {
    account <- status_response$content$response$account
    if (!is.null(account)) {
      cat("   Account:", account$firstname, account$lastname, "\n")
      cat("   Email:", account$email, "\n")
    }
    
    subscription <- status_response$content$response$subscription
    if (!is.null(subscription)) {
      cat("   Plan:", subscription$plan, "\n")
      cat("   Active:", ifelse(subscription$active, green("Yes"), red("No")), "\n")
      cat("   Expires:", subscription$end, "\n")
    }
    
    requests <- status_response$content$response$requests
    if (!is.null(requests)) {
      cat("   Requests today:", requests$current, "/", requests$limit_day, "\n")
    }
  }
} else {
  cat(red("   ✗ API Status check failed\n"))
  cat("   Status code:", status_response$status, "\n")
  if (!is.null(status_response$content$errors)) {
    cat("   Error:", status_response$content$errors, "\n")
  }
}

cat("\n")

# Test 2: Teams Endpoint for each league
cat(yellow("2. Testing Teams Endpoint\n"))

for (league in leagues) {
  cat("\n   ", blue(league$name), "(ID:", league$id, ")\n")
  
  for (season in test_seasons) {
    cat("   Season", season, ": ")
    
    teams_response <- make_request("/teams", list(league = league$id, season = season))
    
    if (teams_response$status == 200) {
      if (!is.null(teams_response$content$results) && teams_response$content$results > 0) {
        team_count <- teams_response$content$results
        cat(green(paste0("✓ ", team_count, " teams found")))
        
        # Store results
        results[[paste0("teams_", league$id, "_", season)]] <- team_count
        
        # Show sample teams
        if (!is.null(teams_response$content$response) && length(teams_response$content$response) > 0) {
          sample_teams <- head(teams_response$content$response, 3)
          team_names <- sapply(sample_teams, function(t) t$team$name)
          cat(" (e.g.,", paste(team_names, collapse = ", "), ")")
        }
        cat("\n")
      } else {
        cat(yellow("⚠ No teams found\n"))
        results[[paste0("teams_", league$id, "_", season)]] <- 0
      }
    } else {
      cat(red("✗ Failed"), "(Status:", teams_response$status, ")\n")
      results[[paste0("teams_", league$id, "_", season)]] <- -1
    }
  }
}

cat("\n")

# Test 3: Fixtures Endpoint for each league
cat(yellow("3. Testing Fixtures Endpoint\n"))

for (league in leagues) {
  cat("\n   ", blue(league$name), "(ID:", league$id, ")\n")
  
  for (season in test_seasons) {
    cat("   Season", season, ": ")
    
    fixtures_response <- make_request("/fixtures", list(league = league$id, season = season))
    
    if (fixtures_response$status == 200) {
      if (!is.null(fixtures_response$content$results) && fixtures_response$content$results > 0) {
        total_fixtures <- fixtures_response$content$results
        
        # Count finished matches
        finished_count <- 0
        if (!is.null(fixtures_response$content$response)) {
          fixtures <- fixtures_response$content$response
          finished <- sapply(fixtures, function(f) {
            !is.null(f$fixture$status$short) && f$fixture$status$short == "FT"
          })
          finished_count <- sum(finished)
        }
        
        cat(green(paste0("✓ ", total_fixtures, " fixtures")))
        cat(" (", finished_count, " finished)")
        
        # Store results
        results[[paste0("fixtures_", league$id, "_", season)]] <- total_fixtures
        results[[paste0("finished_", league$id, "_", season)]] <- finished_count
        
        cat("\n")
      } else {
        cat(yellow("⚠ No fixtures found\n"))
        results[[paste0("fixtures_", league$id, "_", season)]] <- 0
        results[[paste0("finished_", league$id, "_", season)]] <- 0
      }
    } else {
      cat(red("✗ Failed"), "(Status:", fixtures_response$status, ")\n")
      results[[paste0("fixtures_", league$id, "_", season)]] <- -1
      results[[paste0("finished_", league$id, "_", season)]] <- -1
    }
  }
}

cat("\n")

# Test 4: Current Season Detection
cat(yellow("4. Testing Current Season Detection\n"))

for (league in leagues) {
  cat("\n   ", blue(league$name), ": ")
  
  # Try to get league info
  league_response <- make_request("/leagues", list(id = league$id))
  
  if (league_response$status == 200 && !is.null(league_response$content$response)) {
    if (length(league_response$content$response) > 0) {
      league_info <- league_response$content$response[[1]]
      if (!is.null(league_info$seasons)) {
        current_seasons <- league_info$seasons[league_info$seasons$current == TRUE, ]
        if (nrow(current_seasons) > 0) {
          current_year <- current_seasons$year[1]
          cat(green(paste0("✓ Current season: ", current_year)))
          
          # Check coverage
          coverage <- current_seasons$coverage[1]
          if (!is.null(coverage)) {
            cat(" (fixtures:", ifelse(coverage$fixtures$events, "✓", "✗"),
                ", lineups:", ifelse(coverage$fixtures$lineups, "✓", "✗"),
                ", statistics:", ifelse(coverage$fixtures$statistics_fixtures, "✓", "✗"), ")")
          }
        } else {
          cat(yellow("⚠ No current season marked"))
        }
      }
    }
  } else {
    cat(red("✗ Failed to get league info"))
  }
  cat("\n")
}

# Summary Report
cat("\n", blue("========================================\n"))
cat(blue("Summary Report\n"))
cat(blue("========================================\n\n"))

# Teams summary
cat(yellow("Teams Endpoint Summary:\n"))
for (league in leagues) {
  cat("  ", league$name, ":\n")
  for (season in test_seasons) {
    key <- paste0("teams_", league$id, "_", season)
    if (!is.null(results[[key]])) {
      count <- results[[key]]
      if (count > 0) {
        cat("    ", season, ":", green(paste(count, "teams")), "\n")
      } else if (count == 0) {
        cat("    ", season, ":", yellow("No teams"), "\n")
      } else {
        cat("    ", season, ":", red("Failed"), "\n")
      }
    }
  }
}

cat("\n", yellow("Fixtures Endpoint Summary:\n"))
for (league in leagues) {
  cat("  ", league$name, ":\n")
  for (season in test_seasons) {
    fixtures_key <- paste0("fixtures_", league$id, "_", season)
    finished_key <- paste0("finished_", league$id, "_", season)
    
    if (!is.null(results[[fixtures_key]])) {
      fixtures_count <- results[[fixtures_key]]
      finished_count <- results[[finished_key]]
      
      if (fixtures_count > 0) {
        cat("    ", season, ":", green(paste(fixtures_count, "fixtures")), 
            "(", finished_count, "finished )\n")
      } else if (fixtures_count == 0) {
        cat("    ", season, ":", yellow("No fixtures"), "\n")
      } else {
        cat("    ", season, ":", red("Failed"), "\n")
      }
    }
  }
}

# Recommendations
cat("\n", yellow("Recommendations:\n"))

# Check for seasons with both teams and fixtures
working_seasons <- c()
for (season in test_seasons) {
  has_all_data <- TRUE
  for (league in leagues) {
    teams_key <- paste0("teams_", league$id, "_", season)
    fixtures_key <- paste0("fixtures_", league$id, "_", season)
    
    if (is.null(results[[teams_key]]) || results[[teams_key]] <= 0 ||
        is.null(results[[fixtures_key]]) || results[[fixtures_key]] <= 0) {
      has_all_data <- FALSE
      break
    }
  }
  if (has_all_data) {
    working_seasons <- c(working_seasons, season)
  }
}

if (length(working_seasons) > 0) {
  cat(green("✓"), "Seasons with complete data:", paste(working_seasons, collapse = ", "), "\n")
} else {
  cat(red("✗"), "No seasons have complete data for all leagues\n")
}

# Check for API limits
if (status_response$status == 200 && !is.null(status_response$content$response$requests)) {
  requests <- status_response$content$response$requests
  usage_percent <- round((requests$current / requests$limit_day) * 100, 1)
  
  if (usage_percent > 80) {
    cat(red("⚠"), "API usage is high (", usage_percent, "% of daily limit)\n")
  } else {
    cat(green("✓"), "API usage is healthy (", usage_percent, "% of daily limit)\n")
  }
}

cat("\n", green("Test completed successfully!\n"))

# Save detailed results to file
results_file <- "api_test_results.json"
write(toJSON(results, pretty = TRUE), results_file)
cat("\nDetailed results saved to:", results_file, "\n")