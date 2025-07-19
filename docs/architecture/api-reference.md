# API Reference

Complete API documentation for the League Simulator system.

## Overview

The League Simulator uses two main APIs:
1. **External API**: API-Football via RapidAPI for match data
2. **Internal API**: Future microservices API for system components

## External API - API-Football

### Authentication

All requests require authentication via RapidAPI:

```r
headers <- c(
  "X-RapidAPI-Key" = Sys.getenv("RAPIDAPI_KEY"),
  "X-RapidAPI-Host" = "v3.football.api-sports.io"
)
```

### Base URL

```
https://v3.football.api-sports.io
```

### Endpoints Used

#### 1. Get Teams

Retrieve all teams for a specific league.

**Endpoint:** `GET /teams`

**Parameters:**
- `league` (required): League ID (78=Bundesliga, 79=2.Bundesliga, 80=3.Liga)
- `season` (required): Season year (e.g., 2024)

**Example Request:**
```r
GET("https://v3.football.api-sports.io/teams?league=78&season=2024",
    add_headers(.headers = headers))
```

**Example Response:**
```json
{
  "response": [
    {
      "team": {
        "id": 157,
        "name": "Bayern Munich",
        "code": "BAY",
        "country": "Germany",
        "founded": 1900,
        "national": false,
        "logo": "https://media.api-sports.io/football/teams/157.png"
      },
      "venue": {
        "id": 700,
        "name": "Allianz Arena",
        "address": "Werner-Heisenberg-Allee 25",
        "city": "München",
        "capacity": 75024,
        "surface": "grass",
        "image": "https://media.api-sports.io/football/venues/700.png"
      }
    }
  ]
}
```

#### 2. Get Fixtures

Retrieve all matches for a league and season.

**Endpoint:** `GET /fixtures`

**Parameters:**
- `league` (required): League ID
- `season` (required): Season year
- `status` (optional): Match status (FT=finished, NS=not started)
- `from` (optional): Start date (YYYY-MM-DD)
- `to` (optional): End date (YYYY-MM-DD)

**Example Request:**
```r
GET("https://v3.football.api-sports.io/fixtures?league=78&season=2024",
    add_headers(.headers = headers))
```

**Example Response:**
```json
{
  "response": [
    {
      "fixture": {
        "id": 867945,
        "referee": "Felix Brych",
        "timezone": "UTC",
        "date": "2025-01-18T14:30:00+00:00",
        "timestamp": 1737209400,
        "periods": {
          "first": 1737209400,
          "second": 1737213000
        },
        "venue": {
          "id": 700,
          "name": "Allianz Arena",
          "city": "München"
        },
        "status": {
          "long": "Match Finished",
          "short": "FT",
          "elapsed": 90
        }
      },
      "league": {
        "id": 78,
        "name": "Bundesliga",
        "country": "Germany",
        "logo": "https://media.api-sports.io/football/leagues/78.png",
        "flag": "https://media.api-sports.io/flags/de.svg",
        "season": 2024,
        "round": "Regular Season - 18"
      },
      "teams": {
        "home": {
          "id": 157,
          "name": "Bayern Munich",
          "logo": "https://media.api-sports.io/football/teams/157.png",
          "winner": true
        },
        "away": {
          "id": 165,
          "name": "Borussia Dortmund",
          "logo": "https://media.api-sports.io/football/teams/165.png",
          "winner": false
        }
      },
      "goals": {
        "home": 3,
        "away": 1
      },
      "score": {
        "halftime": {
          "home": 2,
          "away": 0
        },
        "fulltime": {
          "home": 3,
          "away": 1
        },
        "extratime": {
          "home": null,
          "away": null
        },
        "penalty": {
          "home": null,
          "away": null
        }
      }
    }
  ]
}
```

#### 3. Get Standings

Retrieve current league standings.

**Endpoint:** `GET /standings`

**Parameters:**
- `league` (required): League ID
- `season` (required): Season year

**Example Request:**
```r
GET("https://v3.football.api-sports.io/standings?league=78&season=2024",
    add_headers(.headers = headers))
```

**Example Response:**
```json
{
  "response": [
    {
      "league": {
        "id": 78,
        "name": "Bundesliga",
        "country": "Germany",
        "logo": "https://media.api-sports.io/football/leagues/78.png",
        "flag": "https://media.api-sports.io/flags/de.svg",
        "season": 2024,
        "standings": [
          [
            {
              "rank": 1,
              "team": {
                "id": 157,
                "name": "Bayern Munich",
                "logo": "https://media.api-sports.io/football/teams/157.png"
              },
              "points": 45,
              "goalsDiff": 30,
              "group": "Bundesliga",
              "form": "WWWDW",
              "status": "same",
              "description": "Champions League",
              "all": {
                "played": 18,
                "win": 14,
                "draw": 3,
                "lose": 1,
                "goals": {
                  "for": 48,
                  "against": 18
                }
              },
              "home": {
                "played": 9,
                "win": 8,
                "draw": 1,
                "lose": 0,
                "goals": {
                  "for": 28,
                  "against": 8
                }
              },
              "away": {
                "played": 9,
                "win": 6,
                "draw": 2,
                "lose": 1,
                "goals": {
                  "for": 20,
                  "against": 10
                }
              },
              "update": "2025-01-18T17:00:00+00:00"
            }
          ]
        ]
      }
    }
  ]
}
```

### Rate Limits

API-Football enforces the following rate limits:

| Plan | Requests/Day | Requests/Minute |
|------|--------------|-----------------|
| Free | 100 | 10 |
| Basic | 1,000 | 30 |
| Pro | 10,000 | 60 |

### Error Handling

```r
# RCode/api_helpers.R
make_api_request <- function(endpoint, params = list()) {
  response <- GET(
    url = endpoint,
    query = params,
    add_headers(.headers = c(
      "X-RapidAPI-Key" = Sys.getenv("RAPIDAPI_KEY"),
      "X-RapidAPI-Host" = "v3.football.api-sports.io"
    ))
  )
  
  # Check response status
  if (status_code(response) == 429) {
    stop("Rate limit exceeded. Please wait before retrying.")
  }
  
  if (status_code(response) != 200) {
    stop(sprintf("API request failed with status %d: %s", 
                 status_code(response),
                 content(response, "text")))
  }
  
  # Parse response
  result <- content(response, "parsed")
  
  # Check for API errors
  if (!is.null(result$errors) && length(result$errors) > 0) {
    stop(sprintf("API error: %s", result$errors[[1]]))
  }
  
  return(result$response)
}
```

## Internal API (Future Microservices)

### Base URL

```
http://api.league-simulator.internal/v1
```

### Authentication

JWT-based authentication:

```r
headers <- c(
  "Authorization" = paste("Bearer", get_jwt_token()),
  "Content-Type" = "application/json"
)
```

### Simulation Service API

#### 1. Create Simulation Job

Start a new simulation job.

**Endpoint:** `POST /simulation/jobs`

**Request Body:**
```json
{
  "league_id": 78,
  "season": 2025,
  "iterations": 10000,
  "config": {
    "use_current_elo": true,
    "include_injuries": false,
    "home_advantage": 1.1
  }
}
```

**Response:**
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "created_at": "2025-01-19T15:00:00Z",
  "estimated_completion": "2025-01-19T15:10:00Z"
}
```

#### 2. Get Job Status

Check simulation job status.

**Endpoint:** `GET /simulation/jobs/{job_id}`

**Response:**
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "running",
  "progress": {
    "current_iteration": 5432,
    "total_iterations": 10000,
    "percentage": 54.32
  },
  "started_at": "2025-01-19T15:00:05Z",
  "updated_at": "2025-01-19T15:05:30Z"
}
```

#### 3. Get Simulation Results

Retrieve completed simulation results.

**Endpoint:** `GET /simulation/jobs/{job_id}/results`

**Response:**
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "results": {
    "probability_matrix": [[0.892, 0.098, ...], ...],
    "team_rankings": [
      {
        "team_id": 157,
        "team_name": "Bayern Munich",
        "expected_position": 1.23,
        "championship_probability": 0.892,
        "top4_probability": 0.998,
        "relegation_probability": 0.000
      }
    ],
    "metadata": {
      "league_id": 78,
      "season": 2025,
      "iterations": 10000,
      "simulation_time_seconds": 542
    }
  }
}
```

### Data Service API

#### 1. Get Teams

Retrieve team information.

**Endpoint:** `GET /data/teams`

**Query Parameters:**
- `league_id` (optional): Filter by league
- `season` (optional): Filter by season
- `include_elo` (optional): Include ELO ratings

**Response:**
```json
{
  "teams": [
    {
      "id": 157,
      "name": "Bayern Munich",
      "league_id": 78,
      "elo_rating": 1895.23,
      "season": 2025
    }
  ],
  "total": 18,
  "page": 1,
  "per_page": 50
}
```

#### 2. Update Team ELO

Update team ELO rating.

**Endpoint:** `PUT /data/teams/{team_id}/elo`

**Request Body:**
```json
{
  "elo_rating": 1905.45,
  "reason": "match_result",
  "match_id": 867945
}
```

**Response:**
```json
{
  "team_id": 157,
  "old_elo": 1895.23,
  "new_elo": 1905.45,
  "change": 10.22,
  "updated_at": "2025-01-19T15:00:00Z"
}
```

#### 3. Store Match Result

Store match result in database.

**Endpoint:** `POST /data/matches`

**Request Body:**
```json
{
  "match_id": 867945,
  "home_team_id": 157,
  "away_team_id": 165,
  "home_score": 3,
  "away_score": 1,
  "match_date": "2025-01-18T14:30:00Z",
  "league_id": 78,
  "season": 2025
}
```

### Scheduler Service API

#### 1. Get Schedules

List all scheduled jobs.

**Endpoint:** `GET /scheduler/schedules`

**Response:**
```json
{
  "schedules": [
    {
      "id": "bundesliga-daily",
      "league_id": 78,
      "cron": "0 15,18,21 * * *",
      "timezone": "Europe/Berlin",
      "enabled": true,
      "last_run": "2025-01-19T15:00:00Z",
      "next_run": "2025-01-19T18:00:00Z"
    }
  ]
}
```

#### 2. Create Schedule

Create new scheduled job.

**Endpoint:** `POST /scheduler/schedules`

**Request Body:**
```json
{
  "name": "bundesliga-matchday",
  "league_id": 78,
  "cron": "0 15 * * SAT,SUN",
  "timezone": "Europe/Berlin",
  "config": {
    "iterations": 10000,
    "notify_on_completion": true
  }
}
```

### Error Response Format

All API errors follow this format:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid league_id provided",
    "details": {
      "field": "league_id",
      "value": 999,
      "allowed_values": [78, 79, 80]
    }
  },
  "request_id": "req_1234567890",
  "timestamp": "2025-01-19T15:00:00Z"
}
```

### API Client Implementation

```r
# RCode/api_client.R
LeagueSimulatorAPI <- R6::R6Class("LeagueSimulatorAPI",
  public = list(
    base_url = NULL,
    token = NULL,
    
    initialize = function(base_url = "http://api.league-simulator.internal/v1") {
      self$base_url <- base_url
      self$token <- private$get_auth_token()
    },
    
    create_simulation = function(league_id, season, iterations = 10000) {
      response <- POST(
        url = paste0(self$base_url, "/simulation/jobs"),
        body = list(
          league_id = league_id,
          season = season,
          iterations = iterations
        ),
        encode = "json",
        add_headers(Authorization = paste("Bearer", self$token))
      )
      
      private$handle_response(response)
    },
    
    get_job_status = function(job_id) {
      response <- GET(
        url = paste0(self$base_url, "/simulation/jobs/", job_id),
        add_headers(Authorization = paste("Bearer", self$token))
      )
      
      private$handle_response(response)
    }
  ),
  
  private = list(
    get_auth_token = function() {
      # Implement token retrieval logic
      Sys.getenv("API_TOKEN", "")
    },
    
    handle_response = function(response) {
      if (status_code(response) >= 400) {
        error_body <- content(response, "parsed")
        stop(sprintf("API Error %d: %s", 
                     status_code(response),
                     error_body$error$message))
      }
      
      content(response, "parsed")
    }
  )
)

# Usage example
api <- LeagueSimulatorAPI$new()
job <- api$create_simulation(78, 2025)
status <- api$get_job_status(job$job_id)
```

## API Testing

### Test Endpoints

```r
# test_api_connection.R
test_api_endpoints <- function() {
  tests <- list()
  
  # Test external API
  tests$external_api <- tryCatch({
    response <- GET(
      "https://v3.football.api-sports.io/status",
      add_headers("X-RapidAPI-Key" = Sys.getenv("RAPIDAPI_KEY"))
    )
    list(
      status = "success",
      code = status_code(response),
      account = content(response)$response$account
    )
  }, error = function(e) {
    list(status = "error", message = e$message)
  })
  
  # Test internal API (when available)
  tests$internal_api <- tryCatch({
    response <- GET(paste0(Sys.getenv("INTERNAL_API_URL"), "/health"))
    list(
      status = "success",
      code = status_code(response),
      health = content(response)
    )
  }, error = function(e) {
    list(status = "error", message = e$message)
  })
  
  return(tests)
}
```

### Mock API for Testing

```r
# tests/testthat/helper-api-mock.R
with_mock_api <- function(code) {
  httr::with_mock(
    `httr::GET` = function(url, ...) {
      if (grepl("teams", url)) {
        return(mock_teams_response())
      } else if (grepl("fixtures", url)) {
        return(mock_fixtures_response())
      } else if (grepl("standings", url)) {
        return(mock_standings_response())
      }
    },
    code
  )
}

mock_teams_response <- function() {
  structure(
    list(
      status_code = 200,
      headers = list("content-type" = "application/json"),
      content = charToRaw(jsonlite::toJSON(list(
        response = list(
          list(
            team = list(id = 157, name = "Bayern Munich"),
            venue = list(id = 700, name = "Allianz Arena")
          )
        )
      )))
    ),
    class = "response"
  )
}
```

## API Best Practices

### 1. Rate Limiting

```r
# Implement exponential backoff
api_request_with_retry <- function(url, max_retries = 3) {
  for (i in 1:max_retries) {
    response <- tryCatch({
      GET(url, add_headers(.headers = get_api_headers()))
    }, error = function(e) NULL)
    
    if (!is.null(response) && status_code(response) == 200) {
      return(response)
    }
    
    if (!is.null(response) && status_code(response) == 429) {
      wait_time <- 2^i
      message(sprintf("Rate limited. Waiting %d seconds...", wait_time))
      Sys.sleep(wait_time)
    }
  }
  
  stop("Max retries exceeded")
}
```

### 2. Caching

```r
# Cache API responses
cached_api_request <- function(endpoint, cache_duration = 3600) {
  cache_key <- digest::digest(endpoint)
  cache_file <- file.path("cache", paste0(cache_key, ".rds"))
  
  # Check cache
  if (file.exists(cache_file)) {
    cache_data <- readRDS(cache_file)
    if (difftime(Sys.time(), cache_data$timestamp, units = "secs") < cache_duration) {
      return(cache_data$data)
    }
  }
  
  # Make request
  data <- api_request_with_retry(endpoint)
  
  # Save to cache
  saveRDS(list(data = data, timestamp = Sys.time()), cache_file)
  
  return(data)
}
```

### 3. Error Handling

```r
# Comprehensive error handling
safe_api_call <- function(func, ...) {
  result <- tryCatch({
    func(...)
  }, error = function(e) {
    if (grepl("429", e$message)) {
      return(list(error = "rate_limit", retry_after = 60))
    } else if (grepl("401", e$message)) {
      return(list(error = "auth_failed", message = "Check API key"))
    } else if (grepl("500", e$message)) {
      return(list(error = "server_error", message = "API server error"))
    } else {
      return(list(error = "unknown", message = e$message))
    }
  })
  
  return(result)
}
```

## Related Documentation

- [Architecture Overview](overview.md)
- [Data Flow](data-flow.md)
- [Error Handling](../troubleshooting/common-issues.md)
- [API Testing](../testing/api-testing.md)