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
  response <- VERB("GET", url, query = queryString, add_headers('X-RapidAPI-Key' = RAPIDAPI_KEY, 'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'), content_type("application/octet-stream"))

  # convert the retrieved table to a nice table
  
  # get the content as text
  json_content <- content(response, "text")
  
  # parse the JSON content into a list
  parsed_content <- fromJSON(json_content)
  
  # parsed_content is now a list, and you can access its elements
  # For example, to get the fixtures:
  retrieveResults <- parsed_content$response
  
}