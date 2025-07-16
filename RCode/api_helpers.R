# API Helpers
# Rate limiting, error handling, and retry mechanisms for API calls

with_rate_limit <- function(func, delay = 1.5) {
  # Wrapper for API calls with rate limiting
  # Ensures compliance with API limits
  
  # Store last call time globally
  if (!exists(".last_api_call", envir = .GlobalEnv)) {
    assign(".last_api_call", 0, envir = .GlobalEnv)
  }
  
  # Check time since last call
  current_time <- as.numeric(Sys.time())
  last_call <- get(".last_api_call", envir = .GlobalEnv)
  
  time_since_last <- current_time - last_call
  
  if (time_since_last < delay) {
    sleep_time <- delay - time_since_last
    cat("Rate limiting: sleeping for", round(sleep_time, 2), "seconds\n")
    Sys.sleep(sleep_time)
  }
  
  # Execute function
  result <- tryCatch({
    func()
  }, error = function(e) {
    # Update last call time even on error
    assign(".last_api_call", as.numeric(Sys.time()), envir = .GlobalEnv)
    stop(e)
  })
  
  # Update last call time
  assign(".last_api_call", as.numeric(Sys.time()), envir = .GlobalEnv)
  
  return(result)
}

handle_api_error <- function(response, context = "") {
  # Centralized API error handling
  # Provides user-friendly error messages
  
  status_code <- httr::status_code(response)
  
  error_messages <- list(
    "400" = "Bad Request - Invalid parameters",
    "401" = "Unauthorized - Check your API key",
    "403" = "Forbidden - Access denied",
    "404" = "Not Found - Resource not available",
    "429" = "Too Many Requests - Rate limit exceeded",
    "500" = "Internal Server Error - API server error",
    "503" = "Service Unavailable - API temporarily unavailable"
  )
  
  if (status_code == 200) {
    return(NULL)  # No error
  }
  
  base_message <- paste("API Error", status_code)
  
  if (as.character(status_code) %in% names(error_messages)) {
    detailed_message <- error_messages[[as.character(status_code)]]
  } else {
    detailed_message <- "Unknown error"
  }
  
  if (context != "") {
    full_message <- paste(base_message, "in", context, ":", detailed_message)
  } else {
    full_message <- paste(base_message, ":", detailed_message)
  }
  
  # Add specific advice for common errors
  if (status_code == 401) {
    full_message <- paste(full_message, "\nPlease check your RAPIDAPI_KEY environment variable.")
  } else if (status_code == 429) {
    full_message <- paste(full_message, "\nPlease wait and try again later.")
  }
  
  return(full_message)
}

retry_api_call <- function(func, max_retries = 3, base_delay = 2) {
  # Retry mechanism for failed API calls
  # Exponential backoff strategy
  
  for (attempt in 1:max_retries) {
    result <- tryCatch({
      # Execute function with rate limiting
      with_rate_limit(func)
    }, error = function(e) {
      if (attempt == max_retries) {
        # Last attempt failed, re-throw error
        stop(paste("API call failed after", max_retries, "attempts:", e$message))
      }
      
      # Calculate delay with exponential backoff
      delay <- base_delay * (2 ^ (attempt - 1))
      
      cat("API call failed (attempt", attempt, "of", max_retries, "):", e$message, "\n")
      cat("Retrying in", delay, "seconds...\n")
      
      Sys.sleep(delay)
      
      return(NULL)  # Signal to retry
    })
    
    if (!is.null(result)) {
      if (attempt > 1) {
        cat("API call succeeded on attempt", attempt, "\n")
      }
      return(result)
    }
  }
}

validate_api_response <- function(response, expected_fields = NULL) {
  # Validate API response structure
  # Returns validation results
  
  if (is.null(response)) {
    return(list(
      valid = FALSE,
      message = "Response is NULL"
    ))
  }
  
  # Parse JSON if it's a string
  if (is.character(response)) {
    tryCatch({
      response <- jsonlite::fromJSON(response)
    }, error = function(e) {
      return(list(
        valid = FALSE,
        message = paste("Invalid JSON:", e$message)
      ))
    })
  }
  
  # Check for API error indicators
  if (!is.null(response$error)) {
    return(list(
      valid = FALSE,
      message = paste("API returned error:", response$error)
    ))
  }
  
  # Check for expected structure
  if (!is.null(response$response)) {
    data <- response$response
  } else {
    data <- response
  }
  
  if (is.null(data) || length(data) == 0) {
    return(list(
      valid = FALSE,
      message = "No data in response"
    ))
  }
  
  # Check expected fields if provided
  if (!is.null(expected_fields)) {
    missing_fields <- c()
    
    for (field in expected_fields) {
      if (is.null(data[[field]])) {
        missing_fields <- c(missing_fields, field)
      }
    }
    
    if (length(missing_fields) > 0) {
      return(list(
        valid = FALSE,
        message = paste("Missing expected fields:", paste(missing_fields, collapse = ", "))
      ))
    }
  }
  
  return(list(
    valid = TRUE,
    message = "Response validation passed",
    data = data
  ))
}

check_api_connectivity <- function() {
  # Check API connectivity and authentication
  # Returns connectivity status
  
  tryCatch({
    api_key <- Sys.getenv("RAPIDAPI_KEY")
    if (api_key == "") {
      return(list(
        connected = FALSE,
        message = "RAPIDAPI_KEY not set"
      ))
    }
    
    # Test connectivity with status endpoint
    test_call <- function() {
      url <- "https://api-football-v1.p.rapidapi.com/v3/status"
      
      response <- httr::GET(
        url,
        httr::add_headers(
          'X-RapidAPI-Key' = api_key,
          'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
        ),
        httr::timeout(10)  # 10 second timeout
      )
      
      return(response)
    }
    
    # Execute test call with rate limiting
    response <- with_rate_limit(test_call)
    
    if (httr::status_code(response) == 200) {
      content <- httr::content(response, "text", encoding = "UTF-8")
      data <- jsonlite::fromJSON(content)
      
      return(list(
        connected = TRUE,
        message = "API connectivity OK",
        quota_used = data$response$requests$used,
        quota_limit = data$response$requests$limit_day
      ))
    } else {
      error_msg <- handle_api_error(response, "connectivity test")
      return(list(
        connected = FALSE,
        message = error_msg
      ))
    }
    
  }, error = function(e) {
    return(list(
      connected = FALSE,
      message = paste("Connectivity test failed:", e$message)
    ))
  })
}

get_api_quota_status <- function() {
  # Get current API quota usage
  # Returns quota information
  
  connectivity <- check_api_connectivity()
  
  if (!connectivity$connected) {
    return(list(
      error = connectivity$message
    ))
  }
  
  quota_info <- list(
    used = connectivity$quota_used,
    limit = connectivity$quota_limit,
    remaining = connectivity$quota_limit - connectivity$quota_used,
    percentage_used = round((connectivity$quota_used / connectivity$quota_limit) * 100, 2)
  )
  
  return(quota_info)
}

log_api_error <- function(error_msg, context = NULL, response = NULL) {
  # Log API errors for debugging
  # Creates structured error log
  
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  log_entry <- list(
    timestamp = timestamp,
    error = error_msg,
    context = context
  )
  
  # Add response details if available
  if (!is.null(response)) {
    log_entry$status_code <- httr::status_code(response)
    log_entry$headers <- list(httr::headers(response))
  }
  
  # Write to error log
  error_log_file <- "api_errors.log"
  
  if (file.exists(error_log_file)) {
    # Append to existing log
    existing_log <- readLines(error_log_file)
    new_log <- c(existing_log, jsonlite::toJSON(log_entry))
    writeLines(new_log, error_log_file)
  } else {
    # Create new log
    writeLines(jsonlite::toJSON(log_entry), error_log_file)
  }
}

create_api_client <- function() {
  # Create configured API client
  # Returns client object with common settings
  
  api_key <- Sys.getenv("RAPIDAPI_KEY")
  if (api_key == "") {
    stop("RAPIDAPI_KEY environment variable not set")
  }
  
  client <- list(
    base_url = "https://api-football-v1.p.rapidapi.com/v3",
    headers = list(
      'X-RapidAPI-Key' = api_key,
      'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
    ),
    timeout = 30,
    rate_limit_delay = 1.5
  )
  
  return(client)
}

make_api_request <- function(endpoint, params = NULL, client = NULL) {
  # Make API request with all error handling and retries
  # Unified API request function
  
  if (is.null(client)) {
    client <- create_api_client()
  }
  
  url <- paste0(client$base_url, endpoint)
  
  # Create request function
  request_func <- function() {
    response <- httr::GET(
      url,
      query = params,
      httr::add_headers(.headers = client$headers),
      httr::timeout(client$timeout)
    )
    
    # Check for errors
    error_msg <- handle_api_error(response, paste("endpoint:", endpoint))
    if (!is.null(error_msg)) {
      stop(error_msg)
    }
    
    return(response)
  }
  
  # Execute with retry logic
  response <- retry_api_call(request_func)
  
  # Parse and validate response
  content <- httr::content(response, "text", encoding = "UTF-8")
  data <- jsonlite::fromJSON(content)
  
  validation <- validate_api_response(data)
  if (!validation$valid) {
    stop(paste("Response validation failed:", validation$message))
  }
  
  return(data)
}