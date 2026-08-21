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

# Render the static site from the committed fixture
source("RCode/generate_static_site.R"); e <- new.env(); load("ShinyApp/data/Ergebnis.Rds", envir = e)
generate_static_site(e$Ergebnis, e$Ergebnis2, e$Ergebnis3, e$Ergebnis3_Aufstieg)

# Run the Shiny preview locally
shiny::runApp("ShinyApp/app.R")
```

```bash
# Build and run the production Docker stack
docker build -t league-simulator:latest .
docker-compose up -d

# Season transition
Rscript scripts/season_transition.R 2025 2026 --non-interactive
```

## Architecture

Four main components:
1. **Simulation Engine** - Rust-based Monte Carlo simulations with ELO ratings (REST seam at `localhost:8080`)
2. **Scheduler** - Automated updates at match times (Berlin timezone)
3. **Season Transition** - Handles promotions/relegations between seasons
4. **Static Site** - three HTML pages + PNG heatmaps rendered by the scheduler into `STATIC_SITE_DIR`, served by Caddy at fussball.csdatascience.de (`ShinyApp/app.R` is a local preview only)

For detailed architecture, see @docs/architecture/overview.md

## Required Environment

```bash
RAPIDAPI_KEY=your_api_key  # Required for API-Football access
```

For all environment variables, see @docs/deployment/quick-start.md

## Conventions

Shared vocabulary lives in `CONTEXT.md`; architecture decisions in `docs/adr/`.

When adding helper functions in `RCode/` that operators run outside the production call graph: provide a `scripts/` wrapper, document it in `docs/user-guide/`, default destructive operations to dry-run with explicit `--confirm`.

## Current Status

- **Season**: 2026-2027 (`SEASON=2026`)
- **API**: api-football via RapidAPI

