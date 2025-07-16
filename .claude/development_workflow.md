# Development Workflow Guide

## Getting Started

### Prerequisites
- R 4.3.1 or higher
- Docker (for containerized development)
- RapidAPI key for api-football
- shinyapps.io account (for deployment)

### Initial Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd League-Simulator-Update
   ```

2. **Install R dependencies**
   ```r
   packages <- readLines("packagelist.txt")
   packages <- trimws(packages[packages != ""])
   install.packages(packages[!packages %in% installed.packages()[,"Package"]])
   ```

3. **Compile C++ code**
   ```bash
   cd RCode
   R CMD SHLIB SpielNichtSimulieren.cpp
   cd ..
   ```

4. **Set up environment variables**
   ```bash
   export RAPIDAPI_KEY="your-api-key"
   export SHINYAPPS_IO_SECRET="your-shiny-secret"
   export SEASON="2024"
   ```

## Development Workflow

### 1. Feature Development

#### Creating a New Feature Branch
```bash
git checkout -b feature/your-feature-name
```

#### Development Cycle
1. Make changes to relevant R scripts
2. If modifying C++ code, recompile:
   ```bash
   cd RCode && R CMD SHLIB SpielNichtSimulieren.cpp && cd ..
   ```
3. Test locally (see Testing section)
4. Commit changes with descriptive messages

### 2. Testing

#### Run Unit Tests
```r
source("tests/testthat.R")
```

#### Test Specific Functionality
```r
# Test a specific file
testthat::test_file("tests/testthat/test-prozent.R")

# Test simulation locally
source("RCode/leagueSimulatorCPP.R")
# This will run a complete simulation cycle
```

#### Manual Testing Checklist
- [ ] API connection works (check `retrieveResults.R`)
- [ ] ELO calculations update correctly
- [ ] Simulation runs without errors
- [ ] Shiny app displays results properly
- [ ] Scheduler triggers at correct times

### 3. Local Development

#### Running the Shiny App Locally
```r
shiny::runApp("ShinyApp/app.R", port = 3838)
# Access at http://localhost:3838
```

#### Running a Single League Update
```r
# Set environment
Sys.setenv(LEAGUE = "78")  # Bundesliga
Sys.setenv(SEASON = "2024")

# Run update
source("RCode/update_league.R")
```

#### Testing the Scheduler
```r
# Test scheduler logic without waiting
source("RCode/updateScheduler.R")
# Modify time checks for immediate execution
```

### 4. Docker Development

#### Build and Test Locally

**Monolithic Mode:**
```bash
# Build
docker build -t league-simulator:dev .

# Run with test environment
docker run -it --rm \
  -e RAPIDAPI_KEY="$RAPIDAPI_KEY" \
  -e SHINYAPPS_IO_SECRET="$SHINYAPPS_IO_SECRET" \
  -e DURATION=10 \
  -e SEASON=2024 \
  league-simulator:dev
```

**Microservices Mode:**
```bash
# Build services
docker build -f Dockerfile.league -t league-updater:dev .
docker build -f Dockerfile.shiny -t shiny-updater:dev .

# Run with docker-compose (create docker-compose.yml first)
docker-compose up
```

### 5. Code Style Guidelines

#### R Code Conventions
- Use tidyverse style guide
- Functions: camelCase (e.g., `retrieveResults`)
- Variables: snake_case for data frames
- Comments: Explain complex logic
- Use explicit namespace calls for clarity

#### File Organization
- Keep related functions in the same file
- Separate concerns (data retrieval, calculation, visualization)
- Name files descriptively

#### Example Code Style
```r
# Good
retrieveResults <- function(league_id, season) {
  # Fetch match results from API
  api_response <- httr::GET(
    url = paste0(base_url, "/fixtures"),
    query = list(league = league_id, season = season)
  )
  
  # Process response
  results_df <- jsonlite::fromJSON(
    httr::content(api_response, "text")
  )
  
  return(results_df)
}

# Avoid
getData <- function(x,y) {
  d = GET(paste0(url,"/fixtures"),query=list(league=x,season=y))
  fromJSON(content(d,"text"))
}
```

### 6. Debugging

#### Common Issues and Solutions

**API Rate Limit Exceeded**
- Check daily call count in logs
- Reduce update frequency
- Implement caching for development

**Shiny App Not Updating**
- Verify `/ShinyApp/data/Ergebnis.Rds` exists
- Check file permissions
- Ensure `updateShiny.R` runs successfully

**Scheduler Not Triggering**
- Verify timezone settings (Europe/Berlin)
- Check system time
- Review cron expressions in scheduler

#### Debug Tools
```r
# Enable verbose logging
options(verbose = TRUE)

# Debug specific functions
debug(retrieveResults)
# Run function, step through with 'n'
undebug(retrieveResults)

# Check environment
Sys.getenv()
sessionInfo()
```

### 7. Deployment Process

#### Pre-deployment Checklist
- [ ] All tests pass
- [ ] No hardcoded credentials
- [ ] Environment variables documented
- [ ] Docker images build successfully
- [ ] API rate limits considered

#### Deploy to Production

**Via GitHub Actions (Recommended)**
```bash
# Tag release
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
# GitHub Actions will build and push Docker images
```

**Manual Deployment**
```bash
# Deploy to shinyapps.io
Rscript -e "source('RCode/updateShiny.R')"

# Deploy to Kubernetes
kubectl apply -f k8s/k8s-deployment.yaml
```

### 8. Monitoring

#### Health Checks
- Monitor API call counts
- Check Shiny app accessibility
- Verify update timestamps
- Review container logs

#### Log Analysis
```bash
# Docker logs
docker logs <container-id>

# Kubernetes logs
kubectl logs -n league-simulator deployment/league-updater-bundesliga
```

## Troubleshooting Quick Reference

| Issue | Check | Solution |
|-------|-------|----------|
| No simulation results | API key validity | Verify RAPIDAPI_KEY is set |
| Outdated predictions | Scheduler timing | Check timezone and system time |
| C++ errors | Compilation | Recompile with R CMD SHLIB |
| Shiny deploy fails | Credentials | Verify SHINYAPPS_IO_SECRET |
| Missing packages | Dependencies | Run package installation |

## Contributing Guidelines

1. **Before Starting Work**
   - Check existing issues/PRs
   - Discuss major changes first
   - Follow branching strategy

2. **Code Quality**
   - Write tests for new features
   - Update documentation
   - Follow style guidelines
   - No commented-out code

3. **Commit Messages**
   - Use conventional commits
   - Reference issues
   - Be descriptive

4. **Pull Request Process**
   - Fill out PR template
   - Ensure CI passes
   - Request review
   - Address feedback promptly