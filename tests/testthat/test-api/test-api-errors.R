# API Error Handling Tests
# Tests for robust API error handling and recovery

library(testthat)
library(httr)
library(mockery)

context("API Error Handling")

# Mock functions for testing
mock_api_response <- function(status_code, content = NULL, headers = list()) {
  structure(
    list(
      status_code = status_code,
      headers = headers,
      content = content
    ),
    class = "response"
  )
}

# Helper to create mock fixture data
create_mock_fixture <- function(n_games = 10, status = "FT") {
  fixtures <- list()
  for (i in 1:n_games) {
    fixtures[[i]] <- list(
      fixture = list(
        id = i,
        status = list(short = status),
        date = "2024-01-15T15:00:00Z"
      ),
      teams = list(
        home = list(id = i, name = paste("Team", i)),
        away = list(id = i + 1, name = paste("Team", i + 1))
      ),
      goals = list(
        home = sample(0:4, 1),
        away = sample(0:4, 1)
      )
    )
  }
  list(response = fixtures)
}

test_that("API handles rate limiting (429) with retry", {
  # Mock the retrieve function with rate limiting
  attempts <- 0
  
  mock_retrieve_with_retry <- function(url, headers, max_retries = 3, base_delay = 1) {
    attempts <<- attempts + 1
    
    if (attempts < 3) {
      # Return rate limit error
      return(list(
        status_code = 429,
        error = "Rate limit exceeded",
        headers = list(`retry-after` = "2")
      ))
    } else {
      # Success on third attempt
      return(list(
        status_code = 200,
        content = create_mock_fixture()
      ))
    }
  }
  
  # Test the retry logic
  result <- mock_retrieve_with_retry("test_url", list())
  
  expect_equal(result$status_code, 200)
  expect_equal(attempts, 3)
})

test_that("API handles server errors (500, 503) gracefully", {
  # Test 500 Internal Server Error
  error_500 <- mock_api_response(500, content = "Internal Server Error")
  
  handle_api_error <- function(response) {
    if (response$status_code >= 500) {
      return(list(
        success = FALSE,
        error = paste("Server error:", response$status_code),
        should_retry = TRUE
      ))
    }
    return(list(success = TRUE))
  }
  
  result_500 <- handle_api_error(error_500)
  expect_false(result_500$success)
  expect_true(result_500$should_retry)
  expect_match(result_500$error, "Server error: 500")
  
  # Test 503 Service Unavailable
  error_503 <- mock_api_response(503, content = "Service Unavailable")
  result_503 <- handle_api_error(error_503)
  expect_false(result_503$success)
  expect_true(result_503$should_retry)
})

test_that("API handles network timeouts", {
  # Mock a timeout error
  mock_timeout_request <- function(url, timeout = 30) {
    if (timeout < 60) {
      stop("Timeout was reached: [api.example.com] Operation timed out")
    }
    return(mock_api_response(200, create_mock_fixture()))
  }
  
  # Test timeout handling
  expect_error(
    mock_timeout_request("test_url", timeout = 30),
    "Timeout was reached"
  )
  
  # Test with increased timeout
  result <- mock_timeout_request("test_url", timeout = 60)
  expect_equal(result$status_code, 200)
})

test_that("API handles malformed JSON responses", {
  # Test various malformed responses
  malformed_cases <- list(
    list(name = "Invalid JSON", content = "{invalid json}"),
    list(name = "Empty response", content = ""),
    list(name = "HTML error page", content = "<html><body>Error</body></html>"),
    list(name = "Null response", content = NULL)
  )
  
  parse_api_response <- function(content) {
    tryCatch({
      if (is.null(content) || content == "") {
        return(list(success = FALSE, error = "Empty response"))
      }
      
      # Try to parse as JSON
      parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
      return(list(success = TRUE, data = parsed))
    }, error = function(e) {
      return(list(success = FALSE, error = paste("JSON parse error:", e$message)))
    })
  }
  
  for (case in malformed_cases) {
    result <- parse_api_response(case$content)
    expect_false(result$success,
                 info = paste("Failed to handle:", case$name))
    expect_true(!is.null(result$error),
                info = paste("No error message for:", case$name))
  }
})

test_that("API handles authentication errors (401, 403)", {
  # Test 401 Unauthorized
  error_401 <- mock_api_response(401, content = "Unauthorized")
  
  handle_auth_error <- function(response) {
    if (response$status_code == 401) {
      return(list(
        success = FALSE,
        error = "Authentication failed - check API key",
        should_retry = FALSE
      ))
    } else if (response$status_code == 403) {
      return(list(
        success = FALSE,
        error = "Access forbidden - check permissions",
        should_retry = FALSE
      ))
    }
    return(list(success = TRUE))
  }
  
  result_401 <- handle_auth_error(error_401)
  expect_false(result_401$success)
  expect_false(result_401$should_retry)  # No point retrying auth errors
  expect_match(result_401$error, "API key")
  
  # Test 403 Forbidden
  error_403 <- mock_api_response(403)
  result_403 <- handle_auth_error(error_403)
  expect_false(result_403$should_retry)
})

test_that("API validates response structure", {
  # Test cases with missing fields
  invalid_structures <- list(
    list(
      name = "Missing response field",
      data = list()  # No 'response' field
    ),
    list(
      name = "Empty response array",
      data = list(response = list())
    ),
    list(
      name = "Missing teams data",
      data = list(response = list(list(
        fixture = list(status = list(short = "FT")),
        goals = list(home = 1, away = 0)
        # Missing 'teams' field
      )))
    ),
    list(
      name = "Missing fixture status",
      data = list(response = list(list(
        teams = list(
          home = list(id = 1),
          away = list(id = 2)
        ),
        goals = list(home = 1, away = 0)
        # Missing 'fixture' field
      )))
    )
  )
  
  validate_api_structure <- function(data) {
    # Check top-level structure
    if (is.null(data$response)) {
      return(list(valid = FALSE, error = "Missing 'response' field"))
    }
    
    if (length(data$response) == 0) {
      return(list(valid = TRUE, warning = "Empty response"))
    }
    
    # Check each fixture
    for (i in seq_along(data$response)) {
      fixture <- data$response[[i]]
      
      if (is.null(fixture$teams)) {
        return(list(valid = FALSE, error = paste("Missing teams in fixture", i)))
      }
      
      if (is.null(fixture$fixture$status)) {
        return(list(valid = FALSE, error = paste("Missing status in fixture", i)))
      }
    }
    
    return(list(valid = TRUE))
  }
  
  for (case in invalid_structures) {
    result <- validate_api_structure(case$data)
    expect_false(result$valid,
                 info = paste("Should invalidate:", case$name))
  }
  
  # Test valid structure
  valid_data <- create_mock_fixture()
  valid_result <- validate_api_structure(valid_data)
  expect_true(valid_result$valid)
})

test_that("API implements exponential backoff correctly", {
  delays <- numeric()
  
  # Mock sleep function to capture delays
  mock_sleep <- function(seconds) {
    delays <<- c(delays, seconds)
  }
  
  # Exponential backoff implementation
  retry_with_backoff <- function(func, max_attempts = 4, base_delay = 1) {
    for (attempt in 1:max_attempts) {
      result <- func()
      
      if (result$success) {
        return(result)
      }
      
      if (attempt < max_attempts) {
        delay <- base_delay * (2 ^ (attempt - 1))
        mock_sleep(delay)
      }
    }
    
    return(result)
  }
  
  # Mock function that fails 3 times
  attempts <- 0
  mock_failing_func <- function() {
    attempts <<- attempts + 1
    if (attempts < 4) {
      return(list(success = FALSE))
    }
    return(list(success = TRUE))
  }
  
  # Test backoff
  result <- retry_with_backoff(mock_failing_func)
  
  expect_true(result$success)
  expect_equal(length(delays), 3)
  expect_equal(delays, c(1, 2, 4))  # Exponential: 1, 2, 4 seconds
})

test_that("API handles partial data gracefully", {
  # Create fixture with some missing data
  partial_fixture <- list(
    response = list(
      list(
        fixture = list(
          status = list(short = "FT")
        ),
        teams = list(
          home = list(id = 1, name = "Team 1"),
          away = list(id = 2, name = "Team 2")
        ),
        goals = list(home = 2, away = 1)
      ),
      list(
        fixture = list(
          status = list(short = "FT")
        ),
        teams = list(
          home = list(id = 3, name = "Team 3"),
          away = list(id = 4, name = "Team 4")
        ),
        goals = list(home = NULL, away = NULL)  # Missing goals
      ),
      list(
        fixture = list(
          status = list(short = "PST")  # Postponed
        ),
        teams = list(
          home = list(id = 5, name = "Team 5"),
          away = list(id = 6, name = "Team 6")
        )
        # No goals for postponed match
      )
    )
  )
  
  process_fixtures <- function(data) {
    results <- list()
    errors <- list()
    
    for (i in seq_along(data$response)) {
      fixture <- data$response[[i]]
      
      # Skip non-finished games
      if (fixture$fixture$status$short != "FT") {
        next
      }
      
      # Check for required data
      if (is.null(fixture$goals$home) || is.null(fixture$goals$away)) {
        errors[[length(errors) + 1]] <- paste("Missing goals for fixture", i)
        next
      }
      
      results[[length(results) + 1]] <- fixture
    }
    
    return(list(
      results = results,
      errors = errors,
      total = length(data$response),
      processed = length(results)
    ))
  }
  
  result <- process_fixtures(partial_fixture)
  
  expect_equal(result$total, 3)
  expect_equal(result$processed, 1)  # Only first fixture is complete
  expect_equal(length(result$errors), 1)  # One error for missing goals
})