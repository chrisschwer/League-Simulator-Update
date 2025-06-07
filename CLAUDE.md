# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Testing
```r
# Run all tests
source("tests/testthat.R")

# Run specific test file
testthat::test_file("tests/testthat/test-prozent.R")
```

### Docker Operations
```bash
# Build Docker image
docker build -t league-simulator .

# Run container with required environment variables
docker run -e RAPIDAPI_KEY=your_api_key \
           -e SHINYAPPS_IO_SECRET=your_shiny_secret \
           -e DURATION=480 \
           -e SEASON=2024 \
           league-simulator
```

### Local Development
```r
# Install dependencies from packagelist.txt
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])

# Run Shiny app locally
shiny::runApp("ShinyApp/app.R")
```

## Architecture

This is a football league simulation system with three main components:

1. **Simulation Engine (Rcpp)**: Core logic in `RCode/` that uses ELO ratings to simulate match outcomes. Key files:
   - `simulationsCPP.R`: Main simulation orchestrator that runs Monte Carlo simulations
   - `SpielNichtSimulieren.cpp`: Updates ELO ratings based on actual results
   - `leagueSimulatorCPP.R`: Wrapper that coordinates data retrieval and simulation

2. **Scheduler System**: Automated update cycle managed by:
   - `updateScheduler.R`: Runs updates at specific times (15:00, 15:30, 16:00, 17:30, 18:00, 21:00, 23:00 Berlin time)
   - `update_all_leagues_loop.R`: Processes all three leagues (Bundesliga, 2. Bundesliga, 3. Liga)
   - Active window: 14:45-23:00, then sleeps for 3 hours

3. **Web Interface**: Shiny app in `ShinyApp/app.R` that:
   - Displays probability heatmaps for final league standings
   - Shows last update timestamp
   - Reads simulation results from `/ShinyApp/data/Ergebnis.Rds`

## Key Technical Details

- **API Integration**: Uses api-football via RapidAPI (requires `RAPIDAPI_KEY`)
- **ELO System**: Initial ratings in `TeamList_YYYY.csv`, updates based on match results
- **Simulation**: Default 10,000 Monte Carlo iterations per update cycle
- **Deployment**: Automated to shinyapps.io via `updateShiny.R`

## Environment Variables

Required for production:
- `RAPIDAPI_KEY`: API authentication for football data
- `SHINYAPPS_IO_SECRET`: Deployment credentials for shinyapps.io
- `DURATION`: Update cycle duration in minutes (default: 480)
- `SEASON`: Current season year (e.g., "2024")