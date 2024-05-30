retrieveCredits <- function () {
  
  require(httr)
  require(jsonlite)

  # Read the API Key from .REnviron (must exist)
  RAPIDAPI_KEY <- Sys.getenv("RAPIDAPI_KEY")

  # retrieve the complete table of fixtures for league and season

  url <- "https://v3.football.api-sports.io/status"
  
  response <- VERB("GET", url, add_headers('X-RapidAPI-Key' = RAPIDAPI_KEY, 'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'), content_type("application/octet-stream"))

  # convert the retrieved table to a nice table
  
  # get the content as text
  json_content <- content(response, "text")
  
  # parse the JSON content into a list
  parsed_content <- fromJSON(json_content)
  
  # parsed_content is now a list, and you can access its elements
  # For example, to get the fixtures:
  retrieveCredits <- as.integer(parsed_content$response$requests$current)
  
}