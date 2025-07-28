# retry_handler.R
# Centralized retry logic with exponential backoff for API calls and other operations
# Created as part of CI/CD reliability improvements (issue #61)

#' Execute a function with retry logic and exponential backoff
#' 
#' @param fn Function to execute
#' @param max_attempts Maximum number of attempts (default: 3)
#' @param initial_delay Initial delay in seconds (default: 1)
#' @param max_delay Maximum delay in seconds (default: 60)
#' @param backoff_factor Multiplier for exponential backoff (default: 2)
#' @param retry_on Specific error classes to retry on (default: all errors)
#' @param quiet Suppress retry messages (default: FALSE)
#' 
#' @return Result of successful function execution
#' @export
retry_with_backoff <- function(fn, 
                             max_attempts = 3, 
                             initial_delay = 1,
                             max_delay = 60,
                             backoff_factor = 2,
                             retry_on = NULL,
                             quiet = FALSE) {
  
  if (!is.function(fn)) {
    stop("'fn' must be a function")
  }
  
  if (max_attempts < 1) {
    stop("'max_attempts' must be at least 1")
  }
  
  last_error <- NULL
  
  for (attempt in 1:max_attempts) {
    result <- tryCatch({
      fn()
    }, error = function(e) {
      last_error <<- e
      
      # Check if we should retry this specific error
      if (!is.null(retry_on)) {
        should_retry <- FALSE
        for (error_class in retry_on) {
          if (inherits(e, error_class)) {
            should_retry <- TRUE
            break
          }
        }
        if (!should_retry) {
          stop(e)
        }
      }
      
      # Don't retry on the last attempt
      if (attempt < max_attempts) {
        delay <- min(initial_delay * (backoff_factor^(attempt - 1)), max_delay)
        
        if (!quiet) {
          message(sprintf(
            "Attempt %d/%d failed: %s\nRetrying in %.1f seconds...",
            attempt, max_attempts, e$message, delay
          ))
        }
        
        Sys.sleep(delay)
        NULL
      } else {
        stop(e)
      }
    })
    
    if (!is.null(result)) {
      if (!quiet && attempt > 1) {
        message(sprintf("Success on attempt %d", attempt))
      }
      return(result)
    }
  }
  
  # Should never reach here, but just in case
  stop(last_error)
}

#' Retry wrapper specifically for HTTP requests
#' 
#' @param url URL to request
#' @param method HTTP method (GET, POST, etc.)
#' @param headers Named list of headers
#' @param body Request body (for POST/PUT)
#' @param ... Additional arguments passed to httr functions
#' @param max_attempts Maximum retry attempts (default: 3)
#' @param quiet Suppress retry messages (default: FALSE)
#' 
#' @return httr response object
#' @export
retry_http_request <- function(url, 
                             method = "GET",
                             headers = list(),
                             body = NULL,
                             ...,
                             max_attempts = 3,
                             quiet = FALSE) {
  
  if (!requireNamespace("httr", quietly = TRUE)) {
    stop("Package 'httr' is required for HTTP requests")
  }
  
  retry_with_backoff(
    fn = function() {
      response <- switch(toupper(method),
        "GET" = httr::GET(url, httr::add_headers(.headers = headers), ...),
        "POST" = httr::POST(url, httr::add_headers(.headers = headers), body = body, ...),
        "PUT" = httr::PUT(url, httr::add_headers(.headers = headers), body = body, ...),
        "DELETE" = httr::DELETE(url, httr::add_headers(.headers = headers), ...),
        stop(paste("Unsupported HTTP method:", method))
      )
      
      # Check for HTTP errors
      if (httr::http_error(response)) {
        status_code <- httr::status_code(response)
        
        # Don't retry on client errors (4xx) except 429 (rate limit)
        if (status_code >= 400 && status_code < 500 && status_code != 429) {
          httr::stop_for_status(response)
        }
        
        # Retry on server errors (5xx) and rate limits (429)
        error_msg <- paste(
          "HTTP error", status_code, "-",
          httr::http_status(response)$message
        )
        stop(error_msg)
      }
      
      response
    },
    max_attempts = max_attempts,
    initial_delay = 1,
    max_delay = 60,
    backoff_factor = 2,
    quiet = quiet
  )
}

#' Retry wrapper for file operations
#' 
#' @param fn File operation function
#' @param max_attempts Maximum retry attempts (default: 3)
#' @param quiet Suppress retry messages (default: FALSE)
#' 
#' @return Result of file operation
#' @export
retry_file_operation <- function(fn, max_attempts = 3, quiet = FALSE) {
  retry_with_backoff(
    fn = fn,
    max_attempts = max_attempts,
    initial_delay = 0.5,
    max_delay = 5,
    backoff_factor = 2,
    retry_on = c("file_error", "permission_error"),
    quiet = quiet
  )
}

#' Retry wrapper for database operations
#' 
#' @param fn Database operation function
#' @param max_attempts Maximum retry attempts (default: 3)
#' @param quiet Suppress retry messages (default: FALSE)
#' 
#' @return Result of database operation
#' @export
retry_db_operation <- function(fn, max_attempts = 3, quiet = FALSE) {
  retry_with_backoff(
    fn = fn,
    max_attempts = max_attempts,
    initial_delay = 0.1,
    max_delay = 10,
    backoff_factor = 2,
    retry_on = c("database_error", "connection_error", "timeout_error"),
    quiet = quiet
  )
}

#' Enhanced API call wrapper for api-football
#' 
#' @param endpoint API endpoint path
#' @param params Query parameters
#' @param api_key API key (defaults to RAPIDAPI_KEY env var)
#' @param max_attempts Maximum retry attempts (default: 3)
#' 
#' @return Parsed API response
#' @export
api_call_with_retry <- function(endpoint, 
                               params = list(),
                               api_key = Sys.getenv("RAPIDAPI_KEY"),
                               max_attempts = 3) {
  
  if (api_key == "") {
    stop("API key not found. Set RAPIDAPI_KEY environment variable.")
  }
  
  base_url <- "https://v3.football.api-sports.io"
  url <- paste0(base_url, endpoint)
  
  headers <- list(
    "X-RapidAPI-Key" = api_key,
    "X-RapidAPI-Host" = "v3.football.api-sports.io"
  )
  
  response <- retry_http_request(
    url = url,
    method = "GET",
    headers = headers,
    query = params,
    max_attempts = max_attempts
  )
  
  # Parse JSON response
  content <- httr::content(response, "text", encoding = "UTF-8")
  result <- jsonlite::fromJSON(content)
  
  # Check API-specific errors
  if (!is.null(result$errors) && length(result$errors) > 0) {
    stop(paste("API error:", paste(result$errors, collapse = ", ")))
  }
  
  result
}

#' Test retry functionality
#' 
#' @export
test_retry_handler <- function() {
  cat("Testing retry handler...\n\n")
  
  # Test 1: Successful on first try
  cat("Test 1: Successful function\n")
  result <- retry_with_backoff(function() {
    cat("  Executing function...\n")
    return(42)
  }, quiet = FALSE)
  cat("  Result:", result, "\n\n")
  
  # Test 2: Fails twice, succeeds on third
  cat("Test 2: Intermittent failure\n")
  attempt_count <- 0
  result <- retry_with_backoff(function() {
    attempt_count <<- attempt_count + 1
    cat("  Attempt", attempt_count, "\n")
    if (attempt_count < 3) {
      stop("Simulated failure")
    }
    return("Success!")
  }, max_attempts = 5, initial_delay = 0.5, quiet = FALSE)
  cat("  Final result:", result, "\n\n")
  
  # Test 3: Always fails
  cat("Test 3: Persistent failure\n")
  tryCatch({
    retry_with_backoff(function() {
      stop("This always fails")
    }, max_attempts = 2, initial_delay = 0.5, quiet = FALSE)
  }, error = function(e) {
    cat("  Expected error:", e$message, "\n")
  })
  
  cat("\nAll tests completed!\n")
}

# Example usage in other scripts:
# source("RCode/retry_handler.R")
# 
# # Retry API call
# result <- api_call_with_retry("/teams", params = list(league = 78, season = 2025))
# 
# # Retry custom function
# data <- retry_with_backoff(function() {
#   read.csv("potentially_locked_file.csv")
# })
# 
# # Retry with specific error handling
# connection <- retry_with_backoff(
#   function() { dbConnect(...) },
#   retry_on = c("connection_error"),
#   max_attempts = 5
# )