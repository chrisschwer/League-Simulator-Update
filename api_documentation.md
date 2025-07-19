# API-Football v3 Documentation Summary

## Overview
This document contains the most relevant information for the League Simulator project using API-Football v3 via RapidAPI.

## API Access

### Base URL
```
https://api-football-v1.p.rapidapi.com/v3/
```

### Authentication
All requests require these headers:
```
X-RapidAPI-Key: YOUR_RAPIDAPI_KEY
X-RapidAPI-Host: api-football-v1.p.rapidapi.com
```

### Rate Limiting
- Depends on your RapidAPI subscription plan
- Free tier: Limited requests per day
- Check your RapidAPI dashboard for current limits

## German League IDs

Based on the project's usage:
- **Bundesliga**: `78`
- **2. Bundesliga**: `79` 
- **3. Liga**: `80`

## Key Endpoints

### 1. Teams
Get all teams for a specific league and season:
```
GET /teams
Parameters:
  - league: League ID (e.g., 78)
  - season: Year format (e.g., 2024)
```

### 2. Fixtures (Matches)
Get all fixtures/matches for a league and season:
```
GET /fixtures
Parameters:
  - league: League ID
  - season: Year format (e.g., 2024)
```

Response includes:
- `fixture.status.short`: Match status (FT = Full Time)
- `teams.home.id`, `teams.away.id`: Team IDs
- `goals.home`, `goals.away`: Final scores
- `fixture.date`: Match date

### 3. Standings
Get current league standings:
```
GET /standings
Parameters:
  - league: League ID
  - season: Year format
```

### 4. Leagues
Get league information:
```
GET /leagues
Parameters:
  - id: League ID (optional)
  - country: Country name (e.g., "Germany")
```

### 5. Countries
Get all available countries:
```
GET /countries
```

## Important Parameters

### Season Format
- Use **YYYY** format (e.g., `2024` for 2024/25 season)
- NOT "2024-25" or "2024/2025"

### Match Status Codes
- `FT` - Full Time (finished)
- `NS` - Not Started
- `1H` - First Half
- `2H` - Second Half
- `ET` - Extra Time
- `P` - Penalty
- `AET` - After Extra Time
- `LIVE` - In Play

## Response Format

All responses follow this structure:
```json
{
  "get": "endpoint_name",
  "parameters": {
    // Request parameters
  },
  "errors": [],
  "results": 1,
  "paging": {
    "current": 1,
    "total": 1
  },
  "response": [
    // Actual data array
  ]
}
```

## Common Issues & Solutions

### 1. Empty Results
- Check season format (use YYYY not YYYY-YY)
- Verify league ID is correct
- Ensure API key is valid

### 2. 401 Unauthorized
- API key is missing or invalid
- Check RapidAPI subscription status

### 3. Rate Limit Exceeded
- You've exceeded your daily/monthly quota
- Upgrade your RapidAPI plan

## Usage in League Simulator

### Fetching Teams (used in season transition)
```r
url <- "https://api-football-v1.p.rapidapi.com/v3/teams"
queryString <- list(
  league = "78",  # Bundesliga
  season = "2024"
)
response <- VERB("GET", url, 
  query = queryString, 
  add_headers(
    'X-RapidAPI-Key' = RAPIDAPI_KEY, 
    'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
  ), 
  content_type("application/octet-stream")
)
```

### Fetching Match Results (used for ELO calculation)
```r
url <- "https://api-football-v1.p.rapidapi.com/v3/fixtures"
queryString <- list(
  league = "78",
  season = "2024"
)
# Similar request structure
```

## Data Mapping

### Team Response Fields
- `team.id` → TeamID in CSV
- `team.name` → Full team name
- `team.code` → Can be used for short names (3 letters)

### Fixture Response Fields
- `fixture.date` → Match date/time
- `teams.home.id` → Home team ID
- `teams.away.id` → Away team ID  
- `goals.home` → Home team goals
- `goals.away` → Away team goals
- `fixture.status.short` → Match status

## Best Practices

1. **Cache Responses**: Store API responses locally to avoid unnecessary calls
2. **Batch Requests**: Get all data for a season in one call rather than match-by-match
3. **Error Handling**: Always check for API errors before processing response
4. **Season Validation**: Verify season exists before making requests

## Useful Links

- [API-Football Documentation](https://www.api-football.com/documentation-v3)
- [RapidAPI API-Football](https://rapidapi.com/api-sports/api/api-football)
- [API Status Page](https://api-sports.io/status)

## Environment Setup

Add to your `.Renviron` or set before running:
```bash
export RAPIDAPI_KEY="your_api_key_here"
```

## Testing API Connection

Quick test to verify API access:
```r
library(httr)
library(jsonlite)

test_api <- function() {
  url <- "https://api-football-v1.p.rapidapi.com/v3/status"
  response <- VERB("GET", url,
    add_headers(
      'X-RapidAPI-Key' = Sys.getenv("RAPIDAPI_KEY"),
      'X-RapidAPI-Host' = 'api-football-v1.p.rapidapi.com'
    )
  )
  
  if (status_code(response) == 200) {
    content <- fromJSON(content(response, "text"))
    print(content)
  } else {
    print(paste("API Error:", status_code(response)))
  }
}

test_api()
```

## Notes for League Simulator

1. **ELO Calculations**: Require fixtures endpoint with FT (finished) matches only
2. **Season Transitions**: Use teams endpoint to get current squads
3. **League Validation**: Always verify league has started before processing
4. **Second Teams**: Identified by "II" suffix in team names (e.g., "Bayern München II")

This documentation covers the essential API usage for the League Simulator project. For detailed endpoint specifications, refer to the official documentation links above.