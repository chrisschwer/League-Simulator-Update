# League Simulator Project Context

## Project Overview

The League Simulator is a sophisticated football league prediction system that uses ELO ratings and Monte Carlo simulations to predict match outcomes and final league standings for German football leagues (Bundesliga, 2. Bundesliga, and 3. Liga).

## Technology Stack

### Core Technologies
- **R 4.3.1** - Primary programming language
- **Rcpp** - C++ integration for performance-critical ELO calculations
- **Shiny** - Interactive web interface for displaying simulation results
- **Docker** - Containerization supporting both monolithic and microservices architectures
- **Kubernetes** - Orchestration for microservices deployment

### Key R Packages
- ggplot2 - Data visualization
- httr/jsonlite - API integration
- tidyverse - Data manipulation
- rsconnect - Shiny deployment
- testthat - Unit testing framework

### External Dependencies
- **api-football** via RapidAPI - Live match data source
- **shinyapps.io** - Web hosting platform

## Architecture

### Deployment Modes

1. **Monolithic Mode**
   - Single container running all leagues
   - Simpler deployment, easier debugging
   - Uses `updateScheduler.R` as entry point

2. **Microservices Mode**
   - Separate containers per league + Shiny updater
   - Better scalability and fault isolation
   - Kubernetes orchestration with shared volumes

### Core Components

1. **Simulation Engine** (`/RCode/`)
   - `simulationsCPP.R` - Monte Carlo simulation orchestrator (10,000 iterations default)
   - `SpielNichtSimulieren.cpp` - ELO rating updates for completed matches
   - `SpielCPP.R` - Individual match outcome simulation
   - `leagueSimulatorCPP.R` - Main wrapper coordinating data and simulations

2. **Data Pipeline**
   - `retrieveResults.R` - Fetches live match data from API
   - `transform_data.R` - Data transformation utilities
   - `Tabelle.R` - League table calculations
   - Team data stored in `TeamList_YYYY.xlsx/csv`

3. **Scheduling System**
   - **Update Times**: 15:00, 15:30, 16:00, 17:30, 18:00, 21:00, 23:00 (Berlin time)
   - **Active Window**: 14:45-23:00 with 3-hour sleep period
   - League-specific time windows for microservices mode
   - API rate limiting: 30 calls/day/league

4. **Web Interface** (`/ShinyApp/`)
   - `app.R` - Main Shiny application
   - Displays probability heatmaps for final standings
   - Shows last update timestamp
   - Reads from `/ShinyApp/data/Ergebnis.Rds`

## Key Technical Details

### ELO Rating System
- Initial ratings loaded from TeamList files
- Dynamic updates based on match results
- Accounts for home advantage and form

### Simulation Process
1. Fetch latest match results from API
2. Update ELO ratings for completed matches
3. Simulate remaining matches using current ratings
4. Run 10,000 Monte Carlo iterations
5. Calculate probability distributions for final standings
6. Deploy results to Shiny app

### Environment Variables
- `RAPIDAPI_KEY` - API authentication (required)
- `SHINYAPPS_IO_SECRET` - Deployment credentials (required)
- `DURATION` - Update cycle duration in minutes (default: 480)
- `SEASON` - Current season year (e.g., "2024")
- `LEAGUE` - Specific league for microservices mode

## Development Workflow

### Local Development
```r
# Install dependencies
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])

# Run Shiny app locally
shiny::runApp("ShinyApp/app.R")

# Test simulation locally
source("RCode/leagueSimulatorCPP.R")
```

### Testing
```r
# Run all tests
source("tests/testthat.R")

# Run specific test
testthat::test_file("tests/testthat/test-prozent.R")
```

### Docker Operations
```bash
# Monolithic build/run
docker build -t league-simulator .
docker run -e RAPIDAPI_KEY=xxx -e SHINYAPPS_IO_SECRET=xxx league-simulator

# Microservices deployment
kubectl apply -f k8s/k8s-deployment.yaml
```

## Code Conventions

### R Code Style
- Functions use camelCase (e.g., `retrieveResults`)
- Data frames use descriptive names
- Liberal use of tidyverse syntax
- Comments in German and English

### File Organization
- Core logic in `/RCode/`
- Web interface in `/ShinyApp/`
- Tests in `/tests/testthat/`
- Team data in root directory

### Error Handling
- API failures handled gracefully with retries
- Missing data handled with defensive programming
- Logging to console for debugging

## Common Tasks

### Adding a New League
1. Add league ID to configuration
2. Create TeamList file with initial ELO ratings
3. Update schedulers to include new league
4. Test API integration

### Modifying Simulation Parameters
1. Adjust iteration count in `simulationsCPP.R`
2. Modify ELO update formula in `SpielNichtSimulieren.cpp`
3. Recompile C++ code if needed
4. Test locally before deployment

### Debugging Issues
1. Check scheduler logs for timing issues
2. Verify API key and rate limits
3. Examine `/ShinyApp/data/` for output files
4. Use `leagueSimulatorCPP.R` for isolated testing

## Security Considerations

- API keys stored as environment variables
- No hardcoded credentials in code
- Shiny app is read-only (no user input)
- Docker containers run with minimal privileges

## Performance Notes

- C++ used for computationally intensive ELO calculations
- Parallel processing potential in Monte Carlo simulations
- Shared volumes in Kubernetes for inter-service communication
- Caching of API results to minimize calls

## Known Limitations

- Limited test coverage (only basic unit tests)
- No CI/CD pipeline configured
- Manual deployment process
- Timezone-dependent scheduling
- API rate limits can affect update frequency

## Future Enhancement Opportunities

1. Expand test coverage for simulation logic
2. Implement GitHub Actions for CI/CD
3. Add more sophisticated prediction models
4. Create admin interface for configuration
5. Implement result caching and historical analysis