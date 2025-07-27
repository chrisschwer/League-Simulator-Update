# League Simulator Commands Reference

## Testing Commands

```r
# Run all tests
source("tests/testthat.R")

# Run specific test file
testthat::test_file("tests/testthat/test-prozent.R")

# Test API connection
Rscript test_api_connection.R

# Test ELO calculation
Rscript test_elo_fix.R
```

## Running Updates

```bash
# Single update for initial prognoses
Rscript run_single_update_2025.R

# Continuous update loop (production)
Rscript RCode/updateScheduler.R
```

## Docker Operations

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

## Local Development

```r
# Install dependencies from packagelist.txt
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])

# Run Shiny app locally
shiny::runApp("ShinyApp/app.R")

# Run automated season transition script
Rscript scripts/season_transition.R 2023 2024

# Run season transition with configuration (recommended)
Rscript scripts/season_transition.R 2024 2025 --config examples/team_config.json

# Run season transition non-interactively
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

## Workflow Commands

For detailed workflow commands, see `.claude/workflow.md`. Key commands:
- `/newissue` - Create GitHub issue
- `/makeprogress` - Advance issue through workflow
- `/analyze` - Technical analysis
- `/plan` - Implementation planning
- `/implement` - Code implementation