# Local Development Setup

Guide for setting up the League Simulator development environment on your local machine.

## Overview

This guide covers setting up a local development environment for:
- Making code changes
- Running tests
- Debugging issues
- Contributing to the project

## Prerequisites

- Git
- Docker and Docker Compose
- R 4.2+ (for native development)
- RStudio (recommended)
- Text editor (VS Code, Sublime, etc.)

## Development Setup Options

### Option 1: Docker-based Development (Recommended)

Best for consistency and isolation.

#### Setup Steps

```bash
# Clone repository
git clone https://github.com/chrisschwer/League-Simulator-Update.git
cd League-Simulator-Update

# Create development environment file
cp .env.example .env.development
echo "ENVIRONMENT=development" >> .env.development

# Build development images
docker-compose -f docker-compose.dev.yml build
```

#### Development Docker Compose

Create `docker-compose.dev.yml`:

```yaml
version: '3.8'

services:
  league-simulator-dev:
    build:
      context: .
      dockerfile: Dockerfile.league
      args:
        - BUILD_ENV=development
    environment:
      - RAPIDAPI_KEY=${RAPIDAPI_KEY}
      - SEASON=${SEASON}
      - ENVIRONMENT=development
    volumes:
      - ./RCode:/app/RCode
      - ./ShinyApp:/app/ShinyApp
      - ./tests:/app/tests
      - ./logs:/app/logs
    command: tail -f /dev/null  # Keep container running
    
  shiny-dev:
    build:
      context: .
      dockerfile: Dockerfile.shiny
    ports:
      - "3838:3838"
    volumes:
      - ./ShinyApp:/app/ShinyApp
    environment:
      - SHINY_LOG_LEVEL=debug
```

#### Running Development Environment

```bash
# Start development containers
docker-compose -f docker-compose.dev.yml up -d

# Enter development container
docker-compose -f docker-compose.dev.yml exec league-simulator-dev bash

# Run R interactively
R

# Or run specific scripts
Rscript test_api_connection.R
```

### Option 2: Native R Development

Best for R package development and debugging.

#### Setup Steps

```bash
# Install R dependencies
Rscript -e "install.packages('renv')"
Rscript -e "renv::restore()"

# Or install from packagelist.txt
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])

# Set up environment variables
cp .env.example .Renviron
# Edit .Renviron with your API keys
```

#### RStudio Configuration

1. Open RStudio
2. File → Open Project → Navigate to repository
3. Tools → Project Options → Build Tools → Enable Rcpp compilation

## Development Workflow

### 1. Create Feature Branch

```bash
# Create new branch
git checkout -b feature/your-feature-name

# Or for bug fixes
git checkout -b fix/issue-description
```

### 2. Make Changes

Common development tasks:

#### Modifying Simulation Logic

```r
# Edit simulation files
# RCode/simulationsCPP.R - Main simulation logic
# RCode/SpielNichtSimulieren.cpp - ELO calculations
# RCode/leagueSimulatorCPP.R - League processing

# Test changes
source("RCode/simulationsCPP.R")
# Run test simulation
```

#### Updating Shiny App

```r
# Edit ShinyApp/app.R

# Test locally
shiny::runApp("ShinyApp/app.R", port = 3838)

# Access at http://localhost:3838
```

#### Adding New Features

```r
# Create new module
# RCode/your_new_module.R

# Add tests
# tests/testthat/test-your_new_module.R

# Update documentation
```

### 3. Running Tests

#### Unit Tests

```bash
# Run all tests
Rscript tests/testthat.R

# Run specific test file
Rscript -e "testthat::test_file('tests/testthat/test-prozent.R')"

# Run with coverage
Rscript -e "covr::package_coverage()"
```

#### Integration Tests

```bash
# API integration test
Rscript test_api_connection.R

# Full simulation test
Rscript run_single_update_2025.R

# Season transition test
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

### 4. Debugging

#### R Debugging

```r
# Add breakpoints in RStudio
browser()  # Add this line where you want to break

# Or use debug()
debug(simulationsCPP)
# Run function to start debugging

# Trace function calls
trace(retrieveResults, tracer = browser)
```

#### Docker Debugging

```bash
# View container logs
docker-compose logs -f league-simulator

# Enter container for debugging
docker-compose exec league-simulator bash

# Check R session info
R -e "sessionInfo()"
```

#### Common Debugging Commands

```r
# Check API connectivity
source("RCode/api_helpers.R")
test_api_connection()

# Verify team data
teams <- read.csv("RCode/TeamList_2025.csv")
str(teams)

# Test ELO calculations
source("RCode/SpielNichtSimulieren.cpp")
# Run test match
```

## Development Environment Variables

Create `.env.development`:

```env
# Development API key (with higher limits)
RAPIDAPI_KEY=your_dev_api_key

# Development settings
ENVIRONMENT=development
LOG_LEVEL=debug
SIMULATION_ITERATIONS=100  # Fewer for faster testing

# Local Shiny settings
SHINY_PORT=3838
SHINY_HOST=0.0.0.0
```

## Code Style Guidelines

### R Code Style

```r
# Function names: snake_case
calculate_elo_rating <- function(rating_a, rating_b) {
  # Implementation
}

# Variable names: snake_case
team_elo <- 1500
match_result <- "home_win"

# Constants: UPPER_CASE
DEFAULT_ELO <- 1500
K_FACTOR <- 32
```

### File Organization

```
RCode/
├── Core functionality (*.R)
├── Rcpp files (*.cpp)
├── Helper modules (*_helpers.R)
├── API modules (api_*.R)
└── Data files (TeamList_*.csv)

tests/
├── testthat/
│   ├── test-*.R (test files)
│   └── fixtures/ (test data)
└── integration tests (standalone)
```

## Development Tools

### Recommended VS Code Extensions

```json
{
  "recommendations": [
    "REditorSupport.r",
    "ms-vscode-remote.remote-containers",
    "yzhang.markdown-all-in-one"
  ]
}
```

### Useful R Packages for Development

```r
# Install development tools
install.packages(c(
  "devtools",    # Package development
  "testthat",    # Testing framework
  "covr",        # Code coverage
  "lintr",       # Code linting
  "profvis",     # Performance profiling
  "bench"        # Benchmarking
))
```

## Performance Profiling

```r
# Profile simulation performance
library(profvis)
profvis({
  source("RCode/simulationsCPP.R")
  simulate_season(league_id = 78, iterations = 1000)
})

# Benchmark different approaches
library(bench)
bench::mark(
  original = simulate_v1(),
  optimized = simulate_v2(),
  iterations = 10
)
```

## Contributing Guidelines

1. **Fork the repository**
2. **Create feature branch**
3. **Write tests first** (TDD)
4. **Implement feature**
5. **Run all tests**
6. **Update documentation**
7. **Submit pull request**

### Pre-commit Checklist

- [ ] All tests pass
- [ ] Code follows style guide
- [ ] Documentation updated
- [ ] No hardcoded values
- [ ] API keys not committed
- [ ] Performance impact assessed

## Troubleshooting Development Issues

| Issue | Solution |
|-------|----------|
| Package installation fails | Check R version, use `renv::restore()` |
| Rcpp compilation errors | Install build tools (Xcode/build-essential) |
| API rate limits in dev | Use mock data or separate dev API key |
| Shiny app not refreshing | Clear browser cache, restart R session |
| Docker volume not syncing | Check Docker Desktop settings, restart Docker |

## Related Documentation

- [Testing Guide](../troubleshooting/debugging.md)
- [API Documentation](../architecture/api-reference.md)
- [Contributing Guidelines](../../CONTRIBUTING.md)
- [Code Style Guide](../../STYLE_GUIDE.md)