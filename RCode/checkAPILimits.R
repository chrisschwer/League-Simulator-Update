# Function to check API rate limits and determine safe number of loops
# Returns the maximum number of loops that can be safely run without exceeding limits

checkAPILimits <- function(ideal_loops, avg_calls_per_loop = 2, safety_margin = 0.9) {
  # Try to make a simple API call to check headers
  api_key <- Sys.getenv("RAPIDAPI_KEY")
  if (api_key == "") {
    warning("No RAPIDAPI_KEY found, returning ideal_loops")
    return(ideal_loops)
  }

  # Get season using same logic as updateScheduler.R
  season <- Sys.getenv("SEASON")
  if (season == "") {
    current_month <- as.numeric(format(Sys.Date(), "%m"))
    current_year <- as.numeric(format(Sys.Date(), "%Y"))

    if (current_month >= 7) {
      season <- as.character(current_year)
    } else {
      season <- as.character(current_year - 1)
    }
  }

  # Reuse rate-limit headers captured by a recent retrieveResults() call
  # instead of spending a request on a dedicated probe.
  if (exists(".api_rate_limit") &&
        !is.null(.api_rate_limit$remaining) &&
        difftime(Sys.time(), .api_rate_limit$as_of, units = "mins") < 10) {
    remaining <- .api_rate_limit$remaining
    limit <- .api_rate_limit$limit
    message(sprintf(
      "API Rate Limit (cached): %d/%d requests remaining",
      remaining, limit
    ))
    safe_loops <- floor((remaining * safety_margin) / avg_calls_per_loop)
    return(min(ideal_loops, safe_loops))
  }

  # Make a lightweight API call (e.g., get current round for one league)
  # This costs 1 API call but gives us the rate limit info
  tryCatch(
    {
      response <- httr::GET(
        url = "https://api-football-v1.p.rapidapi.com/v3/fixtures/rounds",
        httr::add_headers(
          "X-RapidAPI-Key" = api_key,
          "X-RapidAPI-Host" = "api-football-v1.p.rapidapi.com"
        ),
        query = list(
          league = "78", # Bundesliga
          season = season,
          current = "true"
        )
      )

      # Extract rate limit headers
      headers <- httr::headers(response)

      # Get remaining requests
      remaining <- as.numeric(headers$`x-ratelimit-requests-remaining`)
      limit <- as.numeric(headers$`x-ratelimit-requests-limit`)

      if (is.na(remaining)) {
        warning("Could not read rate limit headers, returning ideal_loops")
        return(ideal_loops)
      }

      message(sprintf("API Rate Limit: %d/%d requests remaining", remaining, limit))

      # Calculate safe number of loops
      # Apply safety margin to avoid hitting exact limit
      safe_loops <- floor((remaining * safety_margin) / avg_calls_per_loop)

      # Return minimum of ideal and safe loops
      actual_loops <- min(ideal_loops, safe_loops)

      if (actual_loops < ideal_loops) {
        message(sprintf(
          "Reducing loops from %d to %d to respect API limits",
          ideal_loops, actual_loops
        ))
      } else {
        message(sprintf("Running %d loops (within API limits)", actual_loops))
      }

      return(actual_loops)
    },
    error = function(e) {
      warning(sprintf("Error checking API limits: %s", e$message))
      warning("Falling back to conservative estimate")
      # On error, be conservative - assume free tier limits
      # 100 calls per day / 3 leagues = max 33 loops
      conservative_loops <- min(ideal_loops, 33)
      return(conservative_loops)
    }
  )
}
