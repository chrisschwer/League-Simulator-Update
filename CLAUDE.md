# CLAUDE.md

This file provides essential context for Claude Code when working with the League Simulator codebase.

## Project Overview

League Simulator is a football league prediction system using Monte Carlo simulations and ELO ratings to predict final standings for German football leagues (Bundesliga, 2. Bundesliga, 3. Liga).

## Quick Commands

```r
# Run all tests
source("tests/testthat.R")

# Run a single test file
testthat::test_file("tests/testthat/test-prozent.R")

# Install R dependencies from packagelist.txt
packages <- readLines("packagelist.txt")
install.packages(packages[!packages %in% installed.packages()[,"Package"]])

# Run the Shiny app locally
shiny::runApp("ShinyApp/app.R")
```

```bash
# Run a single update
Rscript run_single_update_2025.R

# Build and run the production Docker stack
docker build -t league-simulator:latest .
docker-compose up -d

# Season transition
Rscript scripts/season_transition.R 2024 2025 --non-interactive
```

## Architecture

Four main components:
1. **Simulation Engine** - Rcpp-based Monte Carlo simulations with ELO ratings
2. **Scheduler** - Automated updates at match times (Berlin timezone)
3. **Season Transition** - Handles promotions/relegations between seasons
4. **Web Interface** - Shiny app displaying probability heatmaps

For detailed architecture, see @docs/architecture/overview.md

## Required Environment

```bash
RAPIDAPI_KEY=your_api_key  # Required for API-Football access
```

For all environment variables, see @docs/deployment/quick-start.md

## Conventions

When adding helper functions in `RCode/` that operators run outside the production call graph: provide a `scripts/` wrapper, document it in `docs/user-guide/`, default destructive operations to dry-run with explicit `--confirm`.

## Current Status

- **Season**: 2024-2025
- **API**: api-football via RapidAPI

