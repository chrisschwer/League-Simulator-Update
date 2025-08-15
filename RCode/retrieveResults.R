retrieveResults <- function (league = "78", season = "2022") {
  
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
  response <- VERB("GET", url, query = queryString, 
                   add_headers('X-RapidAPI-Key' = RAPIDAPI_KEY, 
                              'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'), 
                   content_type("application/octet-stream"))

  # Check response status
  if (status_code(response) != 200) {
    warning(paste("API request failed with status:", status_code(response)))
    return(NULL)
  }
  
  # get the content as text
  json_content <- content(response, "text", encoding = "UTF-8")
  
  # parse the JSON content into a list
  parsed_content <- fromJSON(json_content)
  
  # Check if we have response data
  if (is.null(parsed_content$response) || length(parsed_content$response) == 0) {
    warning("No fixtures found in API response")
    return(NULL)
  }
  
  # Get the fixtures
  fixtures <- parsed_content$response
  
  # Flatten the nested structure to create the expected column names
  # This converts nested lists into flat columns with underscore separators
  if (nrow(fixtures) > 0) {
    # Create flattened data frame with the columns expected by elo_aggregation.R
    retrieveResults <- data.frame(
      fixture_id = fixtures$fixture$id,
      fixture_date = fixtures$fixture$date,
      fixture_status_short = fixtures$fixture$status$short,
      fixture_status_long = fixtures$fixture$status$long,
      fixture_elapsed = fixtures$fixture$status$elapsed,
      teams_home_id = as.character(fixtures$teams$home$id),
      teams_home_name = fixtures$teams$home$name,
      teams_away_id = as.character(fixtures$teams$away$id),
      teams_away_name = fixtures$teams$away$name,
      goals_home = fixtures$goals$home,
      goals_away = fixtures$goals$away,
      stringsAsFactors = FALSE
    )
    
    # Handle any NA values in goals (for matches not yet played)
    retrieveResults$goals_home[is.na(retrieveResults$goals_home)] <- 0
    retrieveResults$goals_away[is.na(retrieveResults$goals_away)] <- 0
    
    return(retrieveResults)
  } else {
    return(NULL)
  }
}