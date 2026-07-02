# Last-seen API-Football rate-limit headers, shared across callers so
# checkAPILimits() can avoid spending a request just to read them.
.api_rate_limit <- new.env(parent = emptyenv())

.record_rate_limit_headers <- function(response) {
  hdrs <- httr::headers(response)
  remaining <- suppressWarnings(as.numeric(hdrs[["x-ratelimit-requests-remaining"]]))
  if (!is.na(remaining)) {
    .api_rate_limit$remaining <- remaining
    .api_rate_limit$limit <- suppressWarnings(as.numeric(hdrs[["x-ratelimit-requests-limit"]]))
    .api_rate_limit$as_of <- Sys.time()
  }
  invisible(NULL)
}

retrieveResults <- function(league = "78", season = "2022") {
  require(httr)
  require(jsonlite)

  # Read the API Key from .REnviron (must exist)
  RAPIDAPI_KEY <- Sys.getenv("RAPIDAPI_KEY")

  # retrieve the complete table of fixtures for league and season
  url <- "https://api-football-v1.p.rapidapi.com/v3/fixtures"
  queryString <- list(
    league = league,
    season = season
  )
  response <- VERB("GET", url,
    query = queryString,
    add_headers(
      "X-RapidAPI-Key" = RAPIDAPI_KEY,
      "X-RapidAPI-Host" = "api-football-v1.p.rapidapi.com"
    ),
    content_type("application/octet-stream")
  )

  # Check response status
  if (status_code(response) != 200) {
    warning(paste("API request failed with status:", status_code(response)))
    return(NULL)
  }

  .record_rate_limit_headers(response)

  # get the content as text
  json_content <- content(response, "text", encoding = "UTF-8")

  # parse the JSON content into a list
  parsed_content <- fromJSON(json_content)

  # Check if we have response data
  if (is.null(parsed_content$response) || length(parsed_content$response) == 0) {
    warning("No fixtures found in API response")
    return(NULL)
  }

  # Return the nested structure as expected by the main loops
  retrieveResults <- parsed_content$response

  return(retrieveResults)
}
